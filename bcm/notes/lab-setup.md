# Lab setup — VM do head node BCM no VirtualBox

Passos para reproduzir o head node de lab. Host: Windows 11 + VirtualBox 7.x
(em Windows Home, VirtualBox convive com o WSL2 via Windows Hypervisor Platform).

## 1. Criar a VM via VBoxManage

```powershell
$vbox = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$name = 'BCM-head'
$vdi  = "C:\Users\$env:USERNAME\VirtualBox VMs\$name\$name.vdi"

& $vbox createvm --name $name --ostype RedHat_64 --register
& $vbox modifyvm $name --memory 6144 --cpus 4 --firmware efi --ioapic on `
    --rtcuseutc on --graphicscontroller vmsvga --vram 32

# 2 NICs: NAT (internet) + rede interna de provisioning
& $vbox modifyvm $name --nic1 nat --nictype1 82540EM `
    --nic2 intnet --intnet2 "bcm-prov" --nictype2 82540EM

# disco dinamico de 60 GB
& $vbox createmedium disk --filename $vdi --size 61440 --format VDI
& $vbox storagectl $name --name "SATA" --add sata --controller IntelAhci --portcount 2 --bootable on
& $vbox storageattach $name --storagectl "SATA" --port 0 --device 0 --type hdd      --medium $vdi
& $vbox storageattach $name --storagectl "SATA" --port 1 --device 0 --type dvddrive --medium emptydrive
& $vbox modifyvm $name --boot1 dvd --boot2 disk
```

## 2. Instalar o BCM

Anexe o ISO do BCM ao DVD e dê boot:

```powershell
& $vbox storageattach $name --storagectl "SATA" --port 1 --device 0 --type dvddrive --medium "C:\path\to\bcm-XX.iso"
& $vbox startvm $name --type gui
```

Escolhas no instalador (lab):
- Cluster name: livre
- Workload manager: **Slurm**
- Network topology: **Type 1** (nós em rede interna privada)
- Head node interfaces: **conferir o mapeamento** (ver troubleshooting #4)
  - `enp0s3` → externalnet (DHCP)
  - `enp0s8` → internalnet (`10.141.255.254`)
- Disk: o disco de 60 GB, layout "One big partition"
- BMC: No (é VM, sem IPMI)
- CUDA: desmarcado (VM sem GPU)

## 3. Pós-instalação

Após instalar, **eject do ISO** para bootar no sistema instalado:

```powershell
& $vbox storageattach $name --storagectl "SATA" --port 1 --device 0 --type dvddrive --medium emptydrive
```

Exponha SSH e User Portal pelo NAT:

```powershell
& $vbox controlvm $name natpf1 "ssh,tcp,127.0.0.1,2222,,22"
& $vbox controlvm $name natpf1 "baseview,tcp,127.0.0.1,8081,,8081"
```

- Console / SSH: `ssh -p 2222 root@localhost`
- User Portal: `https://localhost:8081/userportal/` (com a barra!)

## 4. Licenciamento

O head node instala e roda sem ativação. A licença (`request-license` na VM, usando o
Product Key gerado a partir do PAK no NVIDIA Licensing Portal) é um passo pós-instalação.
A licença gratuita do BCM é vinculada à organização que registrou — atente para a
governança se o registro foi feito com e-mail corporativo.
