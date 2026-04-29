Pub Key generation
exekutieren von proxmox script
/root/psbt-usb.sh signer-in
    Signer: 
        mount
            lsblk
            sudo mkfs.ext4 -L USB /dev/sdb1
            sudo mount /dev/disk/by-label/USB /mnt/usb
        hash-keyGen.sh
/root/psbt-usb.sh keyb
        mount
            sudo mount /dev/disk/by-label/USB /mnt/usb
        hash-keyStore.sh
/root/psbt-usb.sh keyc
        mount
            sudo mount /dev/disk/by-label/USB /mnt/usb
        hash-keyStore.sh



und exportieren
gpg --export --armor KEYB-ID > keyb-pubkey

und auf proxmox host kopieren
gpg --import keyb-pubkey.asc
gpg --edit-key KEYB-ID trust
# trust = 5 (ultimate)

installation des scripts
chmod +x /root/psbt_usbFlow.sh

Mounten + unmouten des USB sticks über die folgenden Befehle möglich
/root/psbt-usb.sh hot
/root/psbt-usb.sh signer-in
/root/psbt-usb.sh keyb
/root/psbt-usb.sh signer-final
/root/psbt-usb.sh hot   # Broadcast

Auf VM 
Für signer
sudo ./psbt-guard.sh approve

Für KeyHolder
psbt-guard verify