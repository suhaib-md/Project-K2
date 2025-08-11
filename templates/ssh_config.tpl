Host *
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    IdentityFile ${private_key}
    User ubuntu

%{ for idx, instance in controllers ~}
Host ${instance.tags.Name}
    HostName ${instance.public_ip}
    User ubuntu

%{ endfor ~}
%{ for idx, instance in workers ~}
Host ${instance.tags.Name}
    HostName ${instance.public_ip}
    User ubuntu

%{ endfor ~}