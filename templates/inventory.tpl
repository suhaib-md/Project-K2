[controllers]
%{ for idx, instance in controllers ~}
${instance.tags.Name} ansible_host=${instance.public_ip} private_ip=${instance.private_ip} instance_id=${instance.id}
%{ endfor ~}

[workers]
%{ for idx, instance in workers ~}
${instance.tags.Name} ansible_host=${instance.public_ip} private_ip=${instance.private_ip} instance_id=${instance.id} pod_cidr=10.200.${idx}.0/24
%{ endfor ~}

[all:vars]
ansible_user=ubuntu
ansible_ssh_private_key_file=k8s-key.pem
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
kubernetes_public_address=${lb_dns}