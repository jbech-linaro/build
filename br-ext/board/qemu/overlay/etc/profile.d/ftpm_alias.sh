alias setup_ftpm='mkdir -p /host && mount -t 9p -o trans=virtio host /host && cd /lib/optee_armtz && ln -sf /host/ms-tpm-20-ref/out/bc50d971-d4c9-42c4-82cb-123456789123.ta bc50d971-d4c9-42c4-82cb-123456789123.ta'

alias ftpm_mod='cd /lib && ln -s /host/linux/lib/modules . && modprobe tpm_ftpm_optee'

alias tss='cd /lib && cp /host/ibmtpm20tss/utils/libibmtss* .'

alias tpm_rand='cd /host/ibmtpm20tss/utils && ./getrandom -by 8'

alias ftpm='setup_ftpm && ftpm_mod && tss && tpm_rand'

alias ll='ls -al'
