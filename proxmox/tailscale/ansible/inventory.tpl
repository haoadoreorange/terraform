[tailscale]
%{ for vm in vms ~}
${vm.name} ansible_host=${vm.ipv4_addresses[1][0]}
%{ endfor ~}

[tailscale:vars]
ansible_ssh_private_key_file=~/.ssh/tailscale
ansible_user=tailscale
