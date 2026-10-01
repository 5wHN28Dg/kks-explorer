#!/bin/sh
# Create a Windows test VM for apps/windows/e2e (decision 0033): an unattended install with a local account (kks),
# auto-logon and OpenSSH Server with your key. Usage: make-vm.sh win10|win11 ISO [name]
# Windows 11: the Enterprise evaluation ISO (Microsoft Evaluation Center, 90 days). Windows 10: the 22H2 ISO from
# microsoft.com/software-download/windows10ISO (check its SHA-256 on that page), installed unactivated: the answer file
# names Windows 10 Pro with Microsoft's published KMS client setup key, which activates nothing by itself.
set -eu
kind=$1; iso=$2; name=${3:-kks-$kind}
here=$(cd "$(dirname "$0")" && pwd)
key=${KKS_VM_KEY:-$HOME/.ssh/kks_vm}
[ -f "$key" ] || ssh-keygen -t ed25519 -N "" -f "$key" -C kks-vm-tests
work=$(mktemp -d)
cp "$here/autounattend-$kind.xml" "$work/autounattend.xml"
sed "s|@SSH_PUBLIC_KEY@|$(cat "$key.pub")|" "$here/setup.ps1.in" > "$work/setup.ps1"
dir=${KKS_VM_DIR:-$HOME/vms}
mkdir -p "$dir"
xorriso -as mkisofs -quiet -J -r -V UNATTEND -o "$dir/unattend-$name.iso" "$work"
rm -rf "$work"
setfacl -m u:libvirt-qemu:x "$HOME" && setfacl -m u:libvirt-qemu:rwx "$dir" && setfacl -m u:libvirt-qemu:r "$iso" "$dir/unattend-$name.iso"
virsh -c qemu:///system net-start default 2>/dev/null || true
boot="firmware=efi"
[ "$kind" = win11 ] && boot="firmware=efi,firmware.feature0.name=secure-boot,firmware.feature0.enabled=yes,firmware.feature1.name=enrolled-keys,firmware.feature1.enabled=yes"
virt-install --connect qemu:///system --name "$name" --memory 6144 --vcpus 4 --cpu host-passthrough --os-variant "$kind" \
  --boot "$boot" --features smm.state=on --tpm backend.type=emulator,backend.version=2.0,model=tpm-crb \
  --disk path="$dir/$name.qcow2",size=64,bus=sata,format=qcow2 \
  --disk path="$iso",device=cdrom,bus=sata --disk path="$dir/unattend-$name.iso",device=cdrom,bus=sata \
  --network network=default,model=e1000e --graphics vnc,listen=127.0.0.1 --video vga --noautoconsole
# "Press any key to boot from CD": keep pressing for a while
for i in $(seq 12); do virsh -c qemu:///system send-key "$name" KEY_ENTER >/dev/null 2>&1; sleep 1; done
echo "Installing. When it answers: ssh -i $key kks@\$(virsh -c qemu:///system domifaddr $name | awk '/ipv4/{split(\$4,a,\"/\");print a[1]}')"
