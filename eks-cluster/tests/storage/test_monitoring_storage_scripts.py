#!/usr/bin/env python3
"""Run the teardown script using only temporary files and mocked CLI commands."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


TEARDOWN = Path(__file__).resolve().parents[2] / "eks-cluster-teardown.sh"
PVC_NAME = "prometheus-db-prometheus-monitoring-kube-prometheus-prometheus-0"
PV_NAME = "pvc-monitoring"
VOLUME_ID = "vol-0123456789abcdef0"

MOCK_CLI = r'''#!/usr/bin/env python3
import json, os, pathlib, sys
command = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
state_path = pathlib.Path(os.environ["MOCK_STATE"])
state = json.loads(state_path.read_text())
with open(os.environ["MOCK_LOG"], "a") as log:
    log.write(command + " " + " ".join(args) + "\n")
def output(value="", code=0):
    if value: print(value)
    sys.exit(code)
def save(): state_path.write_text(json.dumps(state))
pv = {"metadata":{"name":"pvc-monitoring"},"spec":{"claimRef":{"namespace":"monitoring","name":"prometheus-db-prometheus-monitoring-kube-prometheus-prometheus-0"}}}
unrelated_pv = {"metadata":{"name":"unrelated-pv"},"spec":{"claimRef":{"namespace":"other","name":"other-claim"}}}
if command == "aws":
    if args[:2] == ["eks", "describe-cluster"]:
        if os.environ.get("CLUSTER_MODE") == "missing":
            output("An error occurred (ResourceNotFoundException): missing cluster", 254)
        if "--query" in args: output("https://oidc.eks.eu-west-2.amazonaws.com/id/test")
        output('{}')
    if args[:2] == ["ec2", "describe-volumes"]:
        state["aws_calls"] += 1; save()
        mode = os.environ.get("AWS_MODE", "deleted")
        if mode == "denied": output("An error occurred (UnauthorizedOperation): access denied", 254)
        if mode == "transient": output("An error occurred (RequestLimitExceeded): retry later", 254)
        if mode == "present" or (mode == "eventual" and state["aws_calls"] == 1): output('{"Volumes":[{}]}')
        output("An error occurred (InvalidVolume.NotFound) when calling DescribeVolumes", 255)
    if args[:2] == ["sts", "get-caller-identity"]: output("123456789012")
    if args[:2] == ["iam", "get-open-id-connect-provider"]: output(code=1)
if command == "kubectl":
    if args[:2] == ["get", "statefulset"]: output("prometheus-db" if state["statefulset"] else "")
    if args[:2] == ["get", "pvc"]:
        if os.environ.get("KUBE_MODE") == "denied": output("Forbidden", 1)
        output(json.dumps({"spec":{"volumeName":"pvc-monitoring"}}) if state["pvc"] else "")
    if args[:2] == ["get", "pv"]:
        if len(args) > 2 and not args[2].startswith("-"):
            output("vol-0123456789abcdef0" if state["pv"] else "")
        pvs = [unrelated_pv] + ([pv] if state["pv"] else [])
        if os.environ.get("KUBE_MODE") == "ambiguous": pvs.append(pv)
        output(json.dumps({"items":pvs}))
    if args[:2] == ["patch", "prometheus"]: output("prometheus patched")
    if args[:2] == ["get", "pod"]:
        output("pod/prometheus-monitoring-kube-prometheus-prometheus-0" if state["pod"] else "")
    if args[0] == "wait":
        if os.environ.get("KUBE_MODE") == "pod-timeout": output("Pod deletion timed out", 1)
        state["pod"] = False; save(); output()
    if args[:2] == ["delete", "pvc"]:
        if os.environ.get("KUBE_MODE") == "pvc-timeout": output("PVC deletion timed out", 1)
        state["pvc"] = False
        if os.environ.get("KUBE_MODE") == "auto-reclaim": state["pv"] = False
        save(); output()
    if args[:2] == ["delete", "pv"]:
        if os.environ.get("KUBE_MODE") == "pv-timeout": output("PV deletion timed out", 1)
        state["pv"] = False; save(); output()
    if args[:2] == ["get", "namespace"]: output(code=1)
    if args[:2] == ["delete", "namespace"] and args[2] == "traefik": output()
if command == "helm" and args[0] in ("status", "uninstall"): output()
if command == "eksctl" and args[:2] == ["get", "iamserviceaccount"]: output("[]")
if command == "sleep": output()
output("Unexpected mocked command: " + command + " " + " ".join(args), 2)
'''


class MonitoringStorageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        scripts = self.root / "scripts"
        scripts.mkdir()
        refresh = scripts / "refresh_eks_cluster_connection.sh"
        refresh.write_text('#!/usr/bin/env bash\necho refresh >> "$MOCK_LOG"\n')
        refresh.chmod(0o755)
        self.teardown = self.root / "eks-cluster-teardown.sh"
        self.teardown.write_text(TEARDOWN.read_text())
        self.teardown.chmod(0o755)
        mock_bin = self.root / "bin"
        mock_bin.mkdir()
        for name in ("aws", "kubectl", "helm", "eksctl", "sleep"):
            path = mock_bin / name
            path.write_text(MOCK_CLI)
            path.chmod(0o755)
        self.log = self.root / "calls.log"
        self.state_path = self.root / "state.json"
        self.state = {"statefulset": True, "pvc": True, "pv": True, "pod": True, "aws_calls": 0}
        self.env = {**os.environ, "PATH": f"{mock_bin}:{os.environ['PATH']}",
                    "MOCK_LOG": str(self.log), "MOCK_STATE": str(self.state_path),
                    "my_eks_cluster_name": "test-cluster", "my_aws_region_name": "eu-west-2"}

    def tearDown(self):
        self.temp.cleanup()

    def run_teardown(self, **extra):
        self.state_path.write_text(json.dumps(self.state))
        return subprocess.run([str(self.teardown)], cwd=self.root, env={**self.env, **extra},
                              text=True, capture_output=True, timeout=15)

    def assert_stopped_before_addons(self, result):
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertNotIn("helm uninstall", self.log.read_text())

    def test_cleanup_order_and_exact_targets(self):
        result = self.run_teardown()
        self.assertEqual(result.returncode, 0, result.stderr)
        log = self.log.read_text()
        steps = ["refresh", "kubectl patch prometheus", "kubectl wait", f"kubectl delete pvc {PVC_NAME} ",
                 f"kubectl delete pv {PV_NAME} ", "aws ec2 describe-volumes", "helm uninstall aws-ebs-csi-driver"]
        positions = [log.index(step) for step in steps]
        self.assertEqual(positions, sorted(positions))
        self.assertIn(VOLUME_ID, result.stdout)
        self.assertIn("--timeout=10m", log)
        self.assertEqual(log.count("--ignore-not-found=true --wait=true --timeout=15m"), 2)
        before_addons = log.split("helm uninstall", 1)[0]
        self.assertEqual(before_addons.count("aws eks describe-cluster --name"), 1)
        self.assertNotIn("delete pv unrelated-pv", log)
        self.assertNotIn("delete-volume", log)

    def test_absent_cluster_skips_all_kubernetes_cleanup(self):
        result = self.run_teardown(CLUSTER_MODE="missing")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("kubectl", self.log.read_text())
        self.assertNotIn("helm", self.log.read_text())

    def test_monitoring_never_deployed_is_noop(self):
        self.state.update(statefulset=False, pvc=False, pv=False, pod=False)
        result = self.run_teardown()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("kubectl delete pvc", self.log.read_text())
        self.assertNotIn("aws ec2 describe-volumes", self.log.read_text())

    def test_absent_pod_still_deletes_storage(self):
        self.state["pod"] = False
        result = self.run_teardown()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("kubectl wait", self.log.read_text())
        self.assertIn(f"kubectl delete pvc {PVC_NAME}", self.log.read_text())

    def test_repeated_cleanup_with_absent_storage_is_noop(self):
        first = self.run_teardown()
        self.assertEqual(first.returncode, 0, first.stderr)
        self.state = json.loads(self.state_path.read_text())
        self.log.write_text("")
        second = self.run_teardown()
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertNotIn("kubectl delete pvc", self.log.read_text())
        self.assertNotIn("aws ec2 describe-volumes", self.log.read_text())

    def test_retry_with_pvc_absent_and_pv_remaining(self):
        self.state["pvc"] = False
        result = self.run_teardown()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(f"kubectl delete pv {PV_NAME}", self.log.read_text())
        self.assertIn(VOLUME_ID, result.stdout)

    def test_automatic_pv_reclamation_allows_explicit_delete_to_noop(self):
        result = self.run_teardown(KUBE_MODE="auto-reclaim")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(f"kubectl delete pv {PV_NAME} --ignore-not-found=true", self.log.read_text())

    def test_kubernetes_errors_stop_before_addon_removal(self):
        for mode in ("denied", "pod-timeout", "pvc-timeout", "pv-timeout"):
            with self.subTest(mode=mode):
                self.log.write_text("")
                result = self.run_teardown(KUBE_MODE=mode)
                self.assert_stopped_before_addons(result)

    def test_ambiguous_remaining_pvs_stop_cleanup(self):
        self.state["pvc"] = False
        result = self.run_teardown(KUBE_MODE="ambiguous")
        self.assert_stopped_before_addons(result)
        self.assertNotIn("kubectl delete pv", self.log.read_text())

    def test_aws_polling_eventually_confirms_deletion(self):
        result = self.run_teardown(AWS_MODE="eventual")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.log.read_text().count("aws ec2 describe-volumes"), 2)
        self.assertEqual(self.log.read_text().count("sleep 5"), 1)

    def test_aws_timeout_stops_before_addon_removal(self):
        result = self.run_teardown(AWS_MODE="present")
        self.assert_stopped_before_addons(result)
        self.assertIn("Timed out after 90 seconds", result.stderr)
        self.assertEqual(self.log.read_text().count("sleep 5"), 18)

    def test_aws_permission_and_transient_errors_are_failures(self):
        for mode in ("denied", "transient"):
            with self.subTest(mode=mode):
                self.log.write_text("")
                result = self.run_teardown(AWS_MODE=mode)
                self.assert_stopped_before_addons(result)
                self.assertNotIn("sleep 5", self.log.read_text())


if __name__ == "__main__":
    unittest.main(verbosity=2)
