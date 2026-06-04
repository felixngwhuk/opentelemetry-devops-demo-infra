# EC2 Bastion Ansible Setup

This Ansible project configures an Ubuntu EC2 instance as a bastion/admin host for AWS EKS operations.

It installs:

- Docker Engine, optional
- AWS CLI v2
- kubectl
- EKS kubeconfig refresh on interactive SSH login
- Terraform
- eksctl
- Helm
- Git

By default, the playbook configures the bastion SSH user to refresh kubeconfig on normal interactive SSH login:

```bash
aws eks update-kubeconfig --region "$aws_region" --name "$eks_cluster_name"
kubectl config get-contexts
kubectl config current-context
kubectl cluster-info
```

The hook is added to the user's `.bashrc` with guards for interactive SSH sessions only, so Ansible's non-interactive SSH commands are not affected.

To disable it:

```yaml
enable_eks_login_refresh: false
```

For the AWS CLI, this playbook does **NOT** configure AWS access keys. The EC2 instance should use an IAM role / instance profile.

## Current version pins

```yaml
kubectl_version: "v1.35.0"
terraform_version: "1.14.3"
eksctl_version: "0.226.0"
helm_version: "v4.1.0"
```

## macOS Ansible control machine setup

Install Ansible on your MacBook:

```bash
brew install ansible
ansible --version
```

Make sure your EC2 key is readable only by you:

```bash
chmod 400 ~/.ssh/devops-demo.pem
```

## AWS security group for SSH Connection

If you want to secure the SSH connection, allow SSH from your current public IP only:

```text
Inbound rule on bastion security group:
Type: SSH
Protocol: TCP
Port: 22
Source: YOUR_PUBLIC_IP/32
```

## First SSH connection

Because `host_key_checking = True`, connect once manually or add the host key:

```bash
ssh -i ~/.ssh/devops-demo.pem ubuntu@YOUR_EC2_PUBLIC_IP
```

Alternatively:

```bash
ssh-keyscan -H YOUR_EC2_PUBLIC_IP >> ~/.ssh/known_hosts
```

## Inventory setup

Copy the example inventory:

```bash
cp inventory.ini.example inventory.ini
```

Edit `inventory.ini`:

```ini
[bastion]
bastion-1 ansible_host=YOUR_EC2_PUBLIC_IP aws_region=YOUR_WORKING_REGION eks_cluster_name=YOUR_WORKING_CLUSTER ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/devops-demo.pem
```

## Test Ansible connectivity

```bash
ansible -i inventory.ini bastion -m ping
```

Expected result:

```text
bastion-1 | SUCCESS => {
  "changed": false,
  "ping": "pong"
}
```

## Run the playbook

Check mode first:

```bash
ansible-playbook -i inventory.ini setup-bastion.yml --check
```

Then run for real:

```bash
ansible-playbook -i inventory.ini setup-bastion.yml
```

## Notes

- The `inventory.ini` file is ignored by Git because it may contain local IPs and key paths.
- Never commit `.pem` files or AWS access keys.
- The bastion EC2 should use an IAM role rather than static AWS credentials.
- After adding the `ubuntu` user to the Docker group, reconnect before running Docker as `ubuntu` without `sudo`.
