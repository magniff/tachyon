    .text
    paddsb %xmm1, %xmm6
    paddsb %xmm12, %xmm0
    paddsb %xmm7, %xmm11
    paddsb %xmm9, %xmm14
    paddsb (%rax), %xmm14
    paddsb 8(%rsp), %xmm3
    paddsb -200(%rbp), %xmm8
    paddsb (%r12), %xmm7
    paddsb 0x40(%r13), %xmm11
    paddsb (%rax,%r9,8), %xmm1
    paddsb 16(%r15,%rcx,2), %xmm14
    paddsb -4(%rdx,%r14,4), %xmm3
    paddsw %xmm1, %xmm6
    paddsw %xmm12, %xmm0
    paddsw %xmm7, %xmm11
    paddsw %xmm9, %xmm14
    paddsw (%rax), %xmm14
    paddsw 8(%rsp), %xmm3
    paddsw -200(%rbp), %xmm8
    paddsw (%r12), %xmm7
    paddsw 0x40(%r13), %xmm11
    paddsw (%rax,%r9,8), %xmm1
    paddsw 16(%r15,%rcx,2), %xmm14
    paddsw -4(%rdx,%r14,4), %xmm3
    paddusb %xmm1, %xmm6
    paddusb %xmm12, %xmm0
    paddusb %xmm7, %xmm11
    paddusb %xmm9, %xmm14
    paddusb (%rax), %xmm14
    paddusb 8(%rsp), %xmm3
    paddusb -200(%rbp), %xmm8
    paddusb (%r12), %xmm7
    paddusb 0x40(%r13), %xmm11
    paddusb (%rax,%r9,8), %xmm1
    paddusb 16(%r15,%rcx,2), %xmm14
    paddusb -4(%rdx,%r14,4), %xmm3
    paddusw %xmm1, %xmm6
    paddusw %xmm12, %xmm0
    paddusw %xmm7, %xmm11
    paddusw %xmm9, %xmm14
    paddusw (%rax), %xmm14
    paddusw 8(%rsp), %xmm3
    paddusw -200(%rbp), %xmm8
    paddusw (%r12), %xmm7
    paddusw 0x40(%r13), %xmm11
    paddusw (%rax,%r9,8), %xmm1
    paddusw 16(%r15,%rcx,2), %xmm14
    paddusw -4(%rdx,%r14,4), %xmm3
    psubsb %xmm1, %xmm6
    psubsb %xmm12, %xmm0
    psubsb %xmm7, %xmm11
    psubsb %xmm9, %xmm14
    psubsb (%rax), %xmm14
    psubsb 8(%rsp), %xmm3
    psubsb -200(%rbp), %xmm8
    psubsb (%r12), %xmm7
    psubsb 0x40(%r13), %xmm11
    psubsb (%rax,%r9,8), %xmm1
    psubsb 16(%r15,%rcx,2), %xmm14
    psubsb -4(%rdx,%r14,4), %xmm3
    psubsw %xmm1, %xmm6
    psubsw %xmm12, %xmm0
    psubsw %xmm7, %xmm11
    psubsw %xmm9, %xmm14
    psubsw (%rax), %xmm14
    psubsw 8(%rsp), %xmm3
    psubsw -200(%rbp), %xmm8
    psubsw (%r12), %xmm7
    psubsw 0x40(%r13), %xmm11
    psubsw (%rax,%r9,8), %xmm1
    psubsw 16(%r15,%rcx,2), %xmm14
    psubsw -4(%rdx,%r14,4), %xmm3
    psubusb %xmm1, %xmm6
    psubusb %xmm12, %xmm0
    psubusb %xmm7, %xmm11
    psubusb %xmm9, %xmm14
    psubusb (%rax), %xmm14
    psubusb 8(%rsp), %xmm3
    psubusb -200(%rbp), %xmm8
    psubusb (%r12), %xmm7
    psubusb 0x40(%r13), %xmm11
    psubusb (%rax,%r9,8), %xmm1
    psubusb 16(%r15,%rcx,2), %xmm14
    psubusb -4(%rdx,%r14,4), %xmm3
    psubusw %xmm1, %xmm6
    psubusw %xmm12, %xmm0
    psubusw %xmm7, %xmm11
    psubusw %xmm9, %xmm14
    psubusw (%rax), %xmm14
    psubusw 8(%rsp), %xmm3
    psubusw -200(%rbp), %xmm8
    psubusw (%r12), %xmm7
    psubusw 0x40(%r13), %xmm11
    psubusw (%rax,%r9,8), %xmm1
    psubusw 16(%r15,%rcx,2), %xmm14
    psubusw -4(%rdx,%r14,4), %xmm3
    pmulhw %xmm1, %xmm6
    pmulhw %xmm12, %xmm0
    pmulhw %xmm7, %xmm11
    pmulhw %xmm9, %xmm14
    pmulhw (%rax), %xmm14
    pmulhw 8(%rsp), %xmm3
    pmulhw -200(%rbp), %xmm8
    pmulhw (%r12), %xmm7
    pmulhw 0x40(%r13), %xmm11
    pmulhw (%rax,%r9,8), %xmm1
    pmulhw 16(%r15,%rcx,2), %xmm14
    pmulhw -4(%rdx,%r14,4), %xmm3
    pmulhuw %xmm1, %xmm6
    pmulhuw %xmm12, %xmm0
    pmulhuw %xmm7, %xmm11
    pmulhuw %xmm9, %xmm14
    pmulhuw (%rax), %xmm14
    pmulhuw 8(%rsp), %xmm3
    pmulhuw -200(%rbp), %xmm8
    pmulhuw (%r12), %xmm7
    pmulhuw 0x40(%r13), %xmm11
    pmulhuw (%rax,%r9,8), %xmm1
    pmulhuw 16(%r15,%rcx,2), %xmm14
    pmulhuw -4(%rdx,%r14,4), %xmm3
    pmuludq %xmm1, %xmm6
    pmuludq %xmm12, %xmm0
    pmuludq %xmm7, %xmm11
    pmuludq %xmm9, %xmm14
    pmuludq (%rax), %xmm14
    pmuludq 8(%rsp), %xmm3
    pmuludq -200(%rbp), %xmm8
    pmuludq (%r12), %xmm7
    pmuludq 0x40(%r13), %xmm11
    pmuludq (%rax,%r9,8), %xmm1
    pmuludq 16(%r15,%rcx,2), %xmm14
    pmuludq -4(%rdx,%r14,4), %xmm3
    pmaddwd %xmm1, %xmm6
    pmaddwd %xmm12, %xmm0
    pmaddwd %xmm7, %xmm11
    pmaddwd %xmm9, %xmm14
    pmaddwd (%rax), %xmm14
    pmaddwd 8(%rsp), %xmm3
    pmaddwd -200(%rbp), %xmm8
    pmaddwd (%r12), %xmm7
    pmaddwd 0x40(%r13), %xmm11
    pmaddwd (%rax,%r9,8), %xmm1
    pmaddwd 16(%r15,%rcx,2), %xmm14
    pmaddwd -4(%rdx,%r14,4), %xmm3
    psadbw %xmm1, %xmm6
    psadbw %xmm12, %xmm0
    psadbw %xmm7, %xmm11
    psadbw %xmm9, %xmm14
    psadbw (%rax), %xmm14
    psadbw 8(%rsp), %xmm3
    psadbw -200(%rbp), %xmm8
    psadbw (%r12), %xmm7
    psadbw 0x40(%r13), %xmm11
    psadbw (%rax,%r9,8), %xmm1
    psadbw 16(%r15,%rcx,2), %xmm14
    psadbw -4(%rdx,%r14,4), %xmm3
    pavgb %xmm1, %xmm6
    pavgb %xmm12, %xmm0
    pavgb %xmm7, %xmm11
    pavgb %xmm9, %xmm14
    pavgb (%rax), %xmm14
    pavgb 8(%rsp), %xmm3
    pavgb -200(%rbp), %xmm8
    pavgb (%r12), %xmm7
    pavgb 0x40(%r13), %xmm11
    pavgb (%rax,%r9,8), %xmm1
    pavgb 16(%r15,%rcx,2), %xmm14
    pavgb -4(%rdx,%r14,4), %xmm3
    pavgw %xmm1, %xmm6
    pavgw %xmm12, %xmm0
    pavgw %xmm7, %xmm11
    pavgw %xmm9, %xmm14
    pavgw (%rax), %xmm14
    pavgw 8(%rsp), %xmm3
    pavgw -200(%rbp), %xmm8
    pavgw (%r12), %xmm7
    pavgw 0x40(%r13), %xmm11
    pavgw (%rax,%r9,8), %xmm1
    pavgw 16(%r15,%rcx,2), %xmm14
    pavgw -4(%rdx,%r14,4), %xmm3
    pminub %xmm1, %xmm6
    pminub %xmm12, %xmm0
    pminub %xmm7, %xmm11
    pminub %xmm9, %xmm14
    pminub (%rax), %xmm14
    pminub 8(%rsp), %xmm3
    pminub -200(%rbp), %xmm8
    pminub (%r12), %xmm7
    pminub 0x40(%r13), %xmm11
    pminub (%rax,%r9,8), %xmm1
    pminub 16(%r15,%rcx,2), %xmm14
    pminub -4(%rdx,%r14,4), %xmm3
    pmaxub %xmm1, %xmm6
    pmaxub %xmm12, %xmm0
    pmaxub %xmm7, %xmm11
    pmaxub %xmm9, %xmm14
    pmaxub (%rax), %xmm14
    pmaxub 8(%rsp), %xmm3
    pmaxub -200(%rbp), %xmm8
    pmaxub (%r12), %xmm7
    pmaxub 0x40(%r13), %xmm11
    pmaxub (%rax,%r9,8), %xmm1
    pmaxub 16(%r15,%rcx,2), %xmm14
    pmaxub -4(%rdx,%r14,4), %xmm3
    pminsw %xmm1, %xmm6
    pminsw %xmm12, %xmm0
    pminsw %xmm7, %xmm11
    pminsw %xmm9, %xmm14
    pminsw (%rax), %xmm14
    pminsw 8(%rsp), %xmm3
    pminsw -200(%rbp), %xmm8
    pminsw (%r12), %xmm7
    pminsw 0x40(%r13), %xmm11
    pminsw (%rax,%r9,8), %xmm1
    pminsw 16(%r15,%rcx,2), %xmm14
    pminsw -4(%rdx,%r14,4), %xmm3
    pmaxsw %xmm1, %xmm6
    pmaxsw %xmm12, %xmm0
    pmaxsw %xmm7, %xmm11
    pmaxsw %xmm9, %xmm14
    pmaxsw (%rax), %xmm14
    pmaxsw 8(%rsp), %xmm3
    pmaxsw -200(%rbp), %xmm8
    pmaxsw (%r12), %xmm7
    pmaxsw 0x40(%r13), %xmm11
    pmaxsw (%rax,%r9,8), %xmm1
    pmaxsw 16(%r15,%rcx,2), %xmm14
    pmaxsw -4(%rdx,%r14,4), %xmm3
    punpckhbw %xmm1, %xmm6
    punpckhbw %xmm12, %xmm0
    punpckhbw %xmm7, %xmm11
    punpckhbw %xmm9, %xmm14
    punpckhbw (%rax), %xmm14
    punpckhbw 8(%rsp), %xmm3
    punpckhbw -200(%rbp), %xmm8
    punpckhbw (%r12), %xmm7
    punpckhbw 0x40(%r13), %xmm11
    punpckhbw (%rax,%r9,8), %xmm1
    punpckhbw 16(%r15,%rcx,2), %xmm14
    punpckhbw -4(%rdx,%r14,4), %xmm3
    punpckhwd %xmm1, %xmm6
    punpckhwd %xmm12, %xmm0
    punpckhwd %xmm7, %xmm11
    punpckhwd %xmm9, %xmm14
    punpckhwd (%rax), %xmm14
    punpckhwd 8(%rsp), %xmm3
    punpckhwd -200(%rbp), %xmm8
    punpckhwd (%r12), %xmm7
    punpckhwd 0x40(%r13), %xmm11
    punpckhwd (%rax,%r9,8), %xmm1
    punpckhwd 16(%r15,%rcx,2), %xmm14
    punpckhwd -4(%rdx,%r14,4), %xmm3
    punpckhdq %xmm1, %xmm6
    punpckhdq %xmm12, %xmm0
    punpckhdq %xmm7, %xmm11
    punpckhdq %xmm9, %xmm14
    punpckhdq (%rax), %xmm14
    punpckhdq 8(%rsp), %xmm3
    punpckhdq -200(%rbp), %xmm8
    punpckhdq (%r12), %xmm7
    punpckhdq 0x40(%r13), %xmm11
    punpckhdq (%rax,%r9,8), %xmm1
    punpckhdq 16(%r15,%rcx,2), %xmm14
    punpckhdq -4(%rdx,%r14,4), %xmm3
    punpckhqdq %xmm1, %xmm6
    punpckhqdq %xmm12, %xmm0
    punpckhqdq %xmm7, %xmm11
    punpckhqdq %xmm9, %xmm14
    punpckhqdq (%rax), %xmm14
    punpckhqdq 8(%rsp), %xmm3
    punpckhqdq -200(%rbp), %xmm8
    punpckhqdq (%r12), %xmm7
    punpckhqdq 0x40(%r13), %xmm11
    punpckhqdq (%rax,%r9,8), %xmm1
    punpckhqdq 16(%r15,%rcx,2), %xmm14
    punpckhqdq -4(%rdx,%r14,4), %xmm3
    packsswb %xmm1, %xmm6
    packsswb %xmm12, %xmm0
    packsswb %xmm7, %xmm11
    packsswb %xmm9, %xmm14
    packsswb (%rax), %xmm14
    packsswb 8(%rsp), %xmm3
    packsswb -200(%rbp), %xmm8
    packsswb (%r12), %xmm7
    packsswb 0x40(%r13), %xmm11
    packsswb (%rax,%r9,8), %xmm1
    packsswb 16(%r15,%rcx,2), %xmm14
    packsswb -4(%rdx,%r14,4), %xmm3
    packssdw %xmm1, %xmm6
    packssdw %xmm12, %xmm0
    packssdw %xmm7, %xmm11
    packssdw %xmm9, %xmm14
    packssdw (%rax), %xmm14
    packssdw 8(%rsp), %xmm3
    packssdw -200(%rbp), %xmm8
    packssdw (%r12), %xmm7
    packssdw 0x40(%r13), %xmm11
    packssdw (%rax,%r9,8), %xmm1
    packssdw 16(%r15,%rcx,2), %xmm14
    packssdw -4(%rdx,%r14,4), %xmm3
    packuswb %xmm1, %xmm6
    packuswb %xmm12, %xmm0
    packuswb %xmm7, %xmm11
    packuswb %xmm9, %xmm14
    packuswb (%rax), %xmm14
    packuswb 8(%rsp), %xmm3
    packuswb -200(%rbp), %xmm8
    packuswb (%r12), %xmm7
    packuswb 0x40(%r13), %xmm11
    packuswb (%rax,%r9,8), %xmm1
    packuswb 16(%r15,%rcx,2), %xmm14
    packuswb -4(%rdx,%r14,4), %xmm3
    andpd %xmm1, %xmm6
    andpd %xmm12, %xmm0
    andpd %xmm7, %xmm11
    andpd %xmm9, %xmm14
    andpd (%rax), %xmm14
    andpd 8(%rsp), %xmm3
    andpd -200(%rbp), %xmm8
    andpd (%r12), %xmm7
    andpd 0x40(%r13), %xmm11
    andpd (%rax,%r9,8), %xmm1
    andpd 16(%r15,%rcx,2), %xmm14
    andpd -4(%rdx,%r14,4), %xmm3
    andnpd %xmm1, %xmm6
    andnpd %xmm12, %xmm0
    andnpd %xmm7, %xmm11
    andnpd %xmm9, %xmm14
    andnpd (%rax), %xmm14
    andnpd 8(%rsp), %xmm3
    andnpd -200(%rbp), %xmm8
    andnpd (%r12), %xmm7
    andnpd 0x40(%r13), %xmm11
    andnpd (%rax,%r9,8), %xmm1
    andnpd 16(%r15,%rcx,2), %xmm14
    andnpd -4(%rdx,%r14,4), %xmm3
    orpd %xmm1, %xmm6
    orpd %xmm12, %xmm0
    orpd %xmm7, %xmm11
    orpd %xmm9, %xmm14
    orpd (%rax), %xmm14
    orpd 8(%rsp), %xmm3
    orpd -200(%rbp), %xmm8
    orpd (%r12), %xmm7
    orpd 0x40(%r13), %xmm11
    orpd (%rax,%r9,8), %xmm1
    orpd 16(%r15,%rcx,2), %xmm14
    orpd -4(%rdx,%r14,4), %xmm3
    minpd %xmm1, %xmm6
    minpd %xmm12, %xmm0
    minpd %xmm7, %xmm11
    minpd %xmm9, %xmm14
    minpd (%rax), %xmm14
    minpd 8(%rsp), %xmm3
    minpd -200(%rbp), %xmm8
    minpd (%r12), %xmm7
    minpd 0x40(%r13), %xmm11
    minpd (%rax,%r9,8), %xmm1
    minpd 16(%r15,%rcx,2), %xmm14
    minpd -4(%rdx,%r14,4), %xmm3
    maxpd %xmm1, %xmm6
    maxpd %xmm12, %xmm0
    maxpd %xmm7, %xmm11
    maxpd %xmm9, %xmm14
    maxpd (%rax), %xmm14
    maxpd 8(%rsp), %xmm3
    maxpd -200(%rbp), %xmm8
    maxpd (%r12), %xmm7
    maxpd 0x40(%r13), %xmm11
    maxpd (%rax,%r9,8), %xmm1
    maxpd 16(%r15,%rcx,2), %xmm14
    maxpd -4(%rdx,%r14,4), %xmm3
    sqrtpd %xmm1, %xmm6
    sqrtpd %xmm12, %xmm0
    sqrtpd %xmm7, %xmm11
    sqrtpd %xmm9, %xmm14
    sqrtpd (%rax), %xmm14
    sqrtpd 8(%rsp), %xmm3
    sqrtpd -200(%rbp), %xmm8
    sqrtpd (%r12), %xmm7
    sqrtpd 0x40(%r13), %xmm11
    sqrtpd (%rax,%r9,8), %xmm1
    sqrtpd 16(%r15,%rcx,2), %xmm14
    sqrtpd -4(%rdx,%r14,4), %xmm3
    unpckhpd %xmm1, %xmm6
    unpckhpd %xmm12, %xmm0
    unpckhpd %xmm7, %xmm11
    unpckhpd %xmm9, %xmm14
    unpckhpd (%rax), %xmm14
    unpckhpd 8(%rsp), %xmm3
    unpckhpd -200(%rbp), %xmm8
    unpckhpd (%r12), %xmm7
    unpckhpd 0x40(%r13), %xmm11
    unpckhpd (%rax,%r9,8), %xmm1
    unpckhpd 16(%r15,%rcx,2), %xmm14
    unpckhpd -4(%rdx,%r14,4), %xmm3
    cvtps2dq %xmm1, %xmm6
    cvtps2dq %xmm12, %xmm0
    cvtps2dq %xmm7, %xmm11
    cvtps2dq %xmm9, %xmm14
    cvtps2dq (%rax), %xmm14
    cvtps2dq 8(%rsp), %xmm3
    cvtps2dq -200(%rbp), %xmm8
    cvtps2dq (%r12), %xmm7
    cvtps2dq 0x40(%r13), %xmm11
    cvtps2dq (%rax,%r9,8), %xmm1
    cvtps2dq 16(%r15,%rcx,2), %xmm14
    cvtps2dq -4(%rdx,%r14,4), %xmm3
    cvttpd2dq %xmm1, %xmm6
    cvttpd2dq %xmm12, %xmm0
    cvttpd2dq %xmm7, %xmm11
    cvttpd2dq %xmm9, %xmm14
    cvttpd2dq (%rax), %xmm14
    cvttpd2dq 8(%rsp), %xmm3
    cvttpd2dq -200(%rbp), %xmm8
    cvttpd2dq (%r12), %xmm7
    cvttpd2dq 0x40(%r13), %xmm11
    cvttpd2dq (%rax,%r9,8), %xmm1
    cvttpd2dq 16(%r15,%rcx,2), %xmm14
    cvttpd2dq -4(%rdx,%r14,4), %xmm3
    cvtpd2ps %xmm1, %xmm6
    cvtpd2ps %xmm12, %xmm0
    cvtpd2ps %xmm7, %xmm11
    cvtpd2ps %xmm9, %xmm14
    cvtpd2ps (%rax), %xmm14
    cvtpd2ps 8(%rsp), %xmm3
    cvtpd2ps -200(%rbp), %xmm8
    cvtpd2ps (%r12), %xmm7
    cvtpd2ps 0x40(%r13), %xmm11
    cvtpd2ps (%rax,%r9,8), %xmm1
    cvtpd2ps 16(%r15,%rcx,2), %xmm14
    cvtpd2ps -4(%rdx,%r14,4), %xmm3
    andps %xmm1, %xmm6
    andps %xmm12, %xmm0
    andps %xmm7, %xmm11
    andps %xmm9, %xmm14
    andps (%rax), %xmm14
    andps 8(%rsp), %xmm3
    andps -200(%rbp), %xmm8
    andps (%r12), %xmm7
    andps 0x40(%r13), %xmm11
    andps (%rax,%r9,8), %xmm1
    andps 16(%r15,%rcx,2), %xmm14
    andps -4(%rdx,%r14,4), %xmm3
    andnps %xmm1, %xmm6
    andnps %xmm12, %xmm0
    andnps %xmm7, %xmm11
    andnps %xmm9, %xmm14
    andnps (%rax), %xmm14
    andnps 8(%rsp), %xmm3
    andnps -200(%rbp), %xmm8
    andnps (%r12), %xmm7
    andnps 0x40(%r13), %xmm11
    andnps (%rax,%r9,8), %xmm1
    andnps 16(%r15,%rcx,2), %xmm14
    andnps -4(%rdx,%r14,4), %xmm3
    orps %xmm1, %xmm6
    orps %xmm12, %xmm0
    orps %xmm7, %xmm11
    orps %xmm9, %xmm14
    orps (%rax), %xmm14
    orps 8(%rsp), %xmm3
    orps -200(%rbp), %xmm8
    orps (%r12), %xmm7
    orps 0x40(%r13), %xmm11
    orps (%rax,%r9,8), %xmm1
    orps 16(%r15,%rcx,2), %xmm14
    orps -4(%rdx,%r14,4), %xmm3
    minps %xmm1, %xmm6
    minps %xmm12, %xmm0
    minps %xmm7, %xmm11
    minps %xmm9, %xmm14
    minps (%rax), %xmm14
    minps 8(%rsp), %xmm3
    minps -200(%rbp), %xmm8
    minps (%r12), %xmm7
    minps 0x40(%r13), %xmm11
    minps (%rax,%r9,8), %xmm1
    minps 16(%r15,%rcx,2), %xmm14
    minps -4(%rdx,%r14,4), %xmm3
    maxps %xmm1, %xmm6
    maxps %xmm12, %xmm0
    maxps %xmm7, %xmm11
    maxps %xmm9, %xmm14
    maxps (%rax), %xmm14
    maxps 8(%rsp), %xmm3
    maxps -200(%rbp), %xmm8
    maxps (%r12), %xmm7
    maxps 0x40(%r13), %xmm11
    maxps (%rax,%r9,8), %xmm1
    maxps 16(%r15,%rcx,2), %xmm14
    maxps -4(%rdx,%r14,4), %xmm3
    sqrtps %xmm1, %xmm6
    sqrtps %xmm12, %xmm0
    sqrtps %xmm7, %xmm11
    sqrtps %xmm9, %xmm14
    sqrtps (%rax), %xmm14
    sqrtps 8(%rsp), %xmm3
    sqrtps -200(%rbp), %xmm8
    sqrtps (%r12), %xmm7
    sqrtps 0x40(%r13), %xmm11
    sqrtps (%rax,%r9,8), %xmm1
    sqrtps 16(%r15,%rcx,2), %xmm14
    sqrtps -4(%rdx,%r14,4), %xmm3
    unpcklps %xmm1, %xmm6
    unpcklps %xmm12, %xmm0
    unpcklps %xmm7, %xmm11
    unpcklps %xmm9, %xmm14
    unpcklps (%rax), %xmm14
    unpcklps 8(%rsp), %xmm3
    unpcklps -200(%rbp), %xmm8
    unpcklps (%r12), %xmm7
    unpcklps 0x40(%r13), %xmm11
    unpcklps (%rax,%r9,8), %xmm1
    unpcklps 16(%r15,%rcx,2), %xmm14
    unpcklps -4(%rdx,%r14,4), %xmm3
    unpckhps %xmm1, %xmm6
    unpckhps %xmm12, %xmm0
    unpckhps %xmm7, %xmm11
    unpckhps %xmm9, %xmm14
    unpckhps (%rax), %xmm14
    unpckhps 8(%rsp), %xmm3
    unpckhps -200(%rbp), %xmm8
    unpckhps (%r12), %xmm7
    unpckhps 0x40(%r13), %xmm11
    unpckhps (%rax,%r9,8), %xmm1
    unpckhps 16(%r15,%rcx,2), %xmm14
    unpckhps -4(%rdx,%r14,4), %xmm3
    cvtdq2ps %xmm1, %xmm6
    cvtdq2ps %xmm12, %xmm0
    cvtdq2ps %xmm7, %xmm11
    cvtdq2ps %xmm9, %xmm14
    cvtdq2ps (%rax), %xmm14
    cvtdq2ps 8(%rsp), %xmm3
    cvtdq2ps -200(%rbp), %xmm8
    cvtdq2ps (%r12), %xmm7
    cvtdq2ps 0x40(%r13), %xmm11
    cvtdq2ps (%rax,%r9,8), %xmm1
    cvtdq2ps 16(%r15,%rcx,2), %xmm14
    cvtdq2ps -4(%rdx,%r14,4), %xmm3
    cvtps2pd %xmm1, %xmm6
    cvtps2pd %xmm12, %xmm0
    cvtps2pd %xmm7, %xmm11
    cvtps2pd %xmm9, %xmm14
    cvtps2pd (%rax), %xmm14
    cvtps2pd 8(%rsp), %xmm3
    cvtps2pd -200(%rbp), %xmm8
    cvtps2pd (%r12), %xmm7
    cvtps2pd 0x40(%r13), %xmm11
    cvtps2pd (%rax,%r9,8), %xmm1
    cvtps2pd 16(%r15,%rcx,2), %xmm14
    cvtps2pd -4(%rdx,%r14,4), %xmm3
    cvttps2dq %xmm1, %xmm6
    cvttps2dq %xmm12, %xmm0
    cvttps2dq %xmm7, %xmm11
    cvttps2dq %xmm9, %xmm14
    cvttps2dq (%rax), %xmm14
    cvttps2dq 8(%rsp), %xmm3
    cvttps2dq -200(%rbp), %xmm8
    cvttps2dq (%r12), %xmm7
    cvttps2dq 0x40(%r13), %xmm11
    cvttps2dq (%rax,%r9,8), %xmm1
    cvttps2dq 16(%r15,%rcx,2), %xmm14
    cvttps2dq -4(%rdx,%r14,4), %xmm3
    cvtdq2pd %xmm1, %xmm6
    cvtdq2pd %xmm12, %xmm0
    cvtdq2pd %xmm7, %xmm11
    cvtdq2pd %xmm9, %xmm14
    cvtdq2pd (%rax), %xmm14
    cvtdq2pd 8(%rsp), %xmm3
    cvtdq2pd -200(%rbp), %xmm8
    cvtdq2pd (%r12), %xmm7
    cvtdq2pd 0x40(%r13), %xmm11
    cvtdq2pd (%rax,%r9,8), %xmm1
    cvtdq2pd 16(%r15,%rcx,2), %xmm14
    cvtdq2pd -4(%rdx,%r14,4), %xmm3
    cvtpd2dq %xmm1, %xmm6
    cvtpd2dq %xmm12, %xmm0
    cvtpd2dq %xmm7, %xmm11
    cvtpd2dq %xmm9, %xmm14
    cvtpd2dq (%rax), %xmm14
    cvtpd2dq 8(%rsp), %xmm3
    cvtpd2dq -200(%rbp), %xmm8
    cvtpd2dq (%r12), %xmm7
    cvtpd2dq 0x40(%r13), %xmm11
    cvtpd2dq (%rax,%r9,8), %xmm1
    cvtpd2dq 16(%r15,%rcx,2), %xmm14
    cvtpd2dq -4(%rdx,%r14,4), %xmm3
    pmovmskb %xmm1, %esi
    pmovmskb %xmm12, %eax
    pmovmskb %xmm7, %r11d
    pmovmskb %xmm9, %r14d
    movmskps %xmm7, %edx
    movmskps %xmm9, %esi
    movmskps %xmm3, %r8d
    movmskps %xmm15, %r11d
    movmskpd %xmm3, %eax
    movmskpd %xmm15, %edx
    movmskpd %xmm1, %r14d
    movmskpd %xmm12, %r8d
    pshuflw $0, %xmm1, %xmm6
    pshuflw $0x7f, %xmm12, %xmm0
    pshuflw $0xff, %xmm7, %xmm11
    pshuflw $0, %xmm9, %xmm14
    pshuflw $0xff, (%rax), %xmm3
    pshuflw $0, 8(%rsp), %xmm8
    pshuflw $0x7f, -200(%rbp), %xmm7
    pshuflw $0xff, (%r12), %xmm11
    pshuflw $0, 0x40(%r13), %xmm1
    pshuflw $0x7f, (%rax,%r9,8), %xmm14
    pshuflw $0xff, 16(%r15,%rcx,2), %xmm3
    pshuflw $0, -4(%rdx,%r14,4), %xmm8
    pshufhw $0, %xmm1, %xmm6
    pshufhw $0x7f, %xmm12, %xmm0
    pshufhw $0xff, %xmm7, %xmm11
    pshufhw $0, %xmm9, %xmm14
    pshufhw $0xff, (%rax), %xmm3
    pshufhw $0, 8(%rsp), %xmm8
    pshufhw $0x7f, -200(%rbp), %xmm7
    pshufhw $0xff, (%r12), %xmm11
    pshufhw $0, 0x40(%r13), %xmm1
    pshufhw $0x7f, (%rax,%r9,8), %xmm14
    pshufhw $0xff, 16(%r15,%rcx,2), %xmm3
    pshufhw $0, -4(%rdx,%r14,4), %xmm8
    shufpd $0, %xmm1, %xmm6
    shufpd $0x7f, %xmm12, %xmm0
    shufpd $0xff, %xmm7, %xmm11
    shufpd $0, %xmm9, %xmm14
    shufpd $0xff, (%rax), %xmm3
    shufpd $0, 8(%rsp), %xmm8
    shufpd $0x7f, -200(%rbp), %xmm7
    shufpd $0xff, (%r12), %xmm11
    shufpd $0, 0x40(%r13), %xmm1
    shufpd $0x7f, (%rax,%r9,8), %xmm14
    shufpd $0xff, 16(%r15,%rcx,2), %xmm3
    shufpd $0, -4(%rdx,%r14,4), %xmm8
    pextrw $0, %xmm1, %esi
    pextrw $0x7f, %xmm12, %eax
    pextrw $0xff, %xmm7, %r11d
    pextrw $0, %xmm9, %r14d
    pinsrw $0xff, %edi, %xmm2
    pinsrw $0, %r9d, %xmm6
    pinsrw $0x7f, %ebx, %xmm8
    pinsrw $0xff, %r15d, %xmm11
    pinsrw $0x7f, (%rax), %xmm3
    pinsrw $0xff, 8(%rsp), %xmm8
    pinsrw $0, -200(%rbp), %xmm7
    pinsrw $0x7f, (%r12), %xmm11
    pinsrw $0xff, 0x40(%r13), %xmm1
    pinsrw $0, (%rax,%r9,8), %xmm14
    pinsrw $0x7f, 16(%r15,%rcx,2), %xmm3
    pinsrw $0xff, -4(%rdx,%r14,4), %xmm8
    psllw $0xff, %xmm7
    psllw $0, %xmm9
    psllw %xmm1, %xmm6
    psllw %xmm12, %xmm0
    psllw %xmm7, %xmm11
    psllw %xmm9, %xmm14
    psllw (%rax), %xmm14
    psllw 8(%rsp), %xmm3
    psllw -200(%rbp), %xmm8
    psllw (%r12), %xmm7
    psllw 0x40(%r13), %xmm11
    psllw (%rax,%r9,8), %xmm1
    psllw 16(%r15,%rcx,2), %xmm14
    psllw -4(%rdx,%r14,4), %xmm3
    psrlw $0, %xmm1
    psrlw $0x7f, %xmm12
    psrlw %xmm3, %xmm0
    psrlw %xmm15, %xmm2
    psrlw %xmm1, %xmm14
    psrlw %xmm12, %xmm8
    psrlw (%rax), %xmm14
    psrlw 8(%rsp), %xmm3
    psrlw -200(%rbp), %xmm8
    psrlw (%r12), %xmm7
    psrlw 0x40(%r13), %xmm11
    psrlw (%rax,%r9,8), %xmm1
    psrlw 16(%r15,%rcx,2), %xmm14
    psrlw -4(%rdx,%r14,4), %xmm3
    psrld $0x7f, %xmm3
    psrld $0xff, %xmm15
    psrld %xmm7, %xmm2
    psrld %xmm9, %xmm6
    psrld %xmm3, %xmm8
    psrld %xmm15, %xmm11
    psrld (%rax), %xmm14
    psrld 8(%rsp), %xmm3
    psrld -200(%rbp), %xmm8
    psrld (%r12), %xmm7
    psrld 0x40(%r13), %xmm11
    psrld (%rax,%r9,8), %xmm1
    psrld 16(%r15,%rcx,2), %xmm14
    psrld -4(%rdx,%r14,4), %xmm3
    psrlq $0xff, %xmm7
    psrlq $0, %xmm9
    psrlq %xmm1, %xmm6
    psrlq %xmm12, %xmm0
    psrlq %xmm7, %xmm11
    psrlq %xmm9, %xmm14
    psrlq (%rax), %xmm14
    psrlq 8(%rsp), %xmm3
    psrlq -200(%rbp), %xmm8
    psrlq (%r12), %xmm7
    psrlq 0x40(%r13), %xmm11
    psrlq (%rax,%r9,8), %xmm1
    psrlq 16(%r15,%rcx,2), %xmm14
    psrlq -4(%rdx,%r14,4), %xmm3
    psraw $0, %xmm1
    psraw $0x7f, %xmm12
    psraw %xmm3, %xmm0
    psraw %xmm15, %xmm2
    psraw %xmm1, %xmm14
    psraw %xmm12, %xmm8
    psraw (%rax), %xmm14
    psraw 8(%rsp), %xmm3
    psraw -200(%rbp), %xmm8
    psraw (%r12), %xmm7
    psraw 0x40(%r13), %xmm11
    psraw (%rax,%r9,8), %xmm1
    psraw 16(%r15,%rcx,2), %xmm14
    psraw -4(%rdx,%r14,4), %xmm3
    psrad $0x7f, %xmm3
    psrad $0xff, %xmm15
    psrad %xmm7, %xmm2
    psrad %xmm9, %xmm6
    psrad %xmm3, %xmm8
    psrad %xmm15, %xmm11
    psrad (%rax), %xmm14
    psrad 8(%rsp), %xmm3
    psrad -200(%rbp), %xmm8
    psrad (%r12), %xmm7
    psrad 0x40(%r13), %xmm11
    psrad (%rax,%r9,8), %xmm1
    psrad 16(%r15,%rcx,2), %xmm14
    psrad -4(%rdx,%r14,4), %xmm3
    pslldq $0xff, %xmm7
    pslldq $0, %xmm9
    psrldq $0, %xmm1
    psrldq $0x7f, %xmm12
    haddps %xmm3, %xmm0
    haddps %xmm15, %xmm2
    haddps %xmm1, %xmm14
    haddps %xmm12, %xmm8
    haddps (%rax), %xmm14
    haddps 8(%rsp), %xmm3
    haddps -200(%rbp), %xmm8
    haddps (%r12), %xmm7
    haddps 0x40(%r13), %xmm11
    haddps (%rax,%r9,8), %xmm1
    haddps 16(%r15,%rcx,2), %xmm14
    haddps -4(%rdx,%r14,4), %xmm3
    hsubps %xmm3, %xmm0
    hsubps %xmm15, %xmm2
    hsubps %xmm1, %xmm14
    hsubps %xmm12, %xmm8
    hsubps (%rax), %xmm14
    hsubps 8(%rsp), %xmm3
    hsubps -200(%rbp), %xmm8
    hsubps (%r12), %xmm7
    hsubps 0x40(%r13), %xmm11
    hsubps (%rax,%r9,8), %xmm1
    hsubps 16(%r15,%rcx,2), %xmm14
    hsubps -4(%rdx,%r14,4), %xmm3
    addsubps %xmm3, %xmm0
    addsubps %xmm15, %xmm2
    addsubps %xmm1, %xmm14
    addsubps %xmm12, %xmm8
    addsubps (%rax), %xmm14
    addsubps 8(%rsp), %xmm3
    addsubps -200(%rbp), %xmm8
    addsubps (%r12), %xmm7
    addsubps 0x40(%r13), %xmm11
    addsubps (%rax,%r9,8), %xmm1
    addsubps 16(%r15,%rcx,2), %xmm14
    addsubps -4(%rdx,%r14,4), %xmm3
    movddup %xmm3, %xmm0
    movddup %xmm15, %xmm2
    movddup %xmm1, %xmm14
    movddup %xmm12, %xmm8
    movddup (%rax), %xmm14
    movddup 8(%rsp), %xmm3
    movddup -200(%rbp), %xmm8
    movddup (%r12), %xmm7
    movddup 0x40(%r13), %xmm11
    movddup (%rax,%r9,8), %xmm1
    movddup 16(%r15,%rcx,2), %xmm14
    movddup -4(%rdx,%r14,4), %xmm3
    haddpd %xmm3, %xmm0
    haddpd %xmm15, %xmm2
    haddpd %xmm1, %xmm14
    haddpd %xmm12, %xmm8
    haddpd (%rax), %xmm14
    haddpd 8(%rsp), %xmm3
    haddpd -200(%rbp), %xmm8
    haddpd (%r12), %xmm7
    haddpd 0x40(%r13), %xmm11
    haddpd (%rax,%r9,8), %xmm1
    haddpd 16(%r15,%rcx,2), %xmm14
    haddpd -4(%rdx,%r14,4), %xmm3
    hsubpd %xmm3, %xmm0
    hsubpd %xmm15, %xmm2
    hsubpd %xmm1, %xmm14
    hsubpd %xmm12, %xmm8
    hsubpd (%rax), %xmm14
    hsubpd 8(%rsp), %xmm3
    hsubpd -200(%rbp), %xmm8
    hsubpd (%r12), %xmm7
    hsubpd 0x40(%r13), %xmm11
    hsubpd (%rax,%r9,8), %xmm1
    hsubpd 16(%r15,%rcx,2), %xmm14
    hsubpd -4(%rdx,%r14,4), %xmm3
    addsubpd %xmm3, %xmm0
    addsubpd %xmm15, %xmm2
    addsubpd %xmm1, %xmm14
    addsubpd %xmm12, %xmm8
    addsubpd (%rax), %xmm14
    addsubpd 8(%rsp), %xmm3
    addsubpd -200(%rbp), %xmm8
    addsubpd (%r12), %xmm7
    addsubpd 0x40(%r13), %xmm11
    addsubpd (%rax,%r9,8), %xmm1
    addsubpd 16(%r15,%rcx,2), %xmm14
    addsubpd -4(%rdx,%r14,4), %xmm3
    movshdup %xmm3, %xmm0
    movshdup %xmm15, %xmm2
    movshdup %xmm1, %xmm14
    movshdup %xmm12, %xmm8
    movshdup (%rax), %xmm14
    movshdup 8(%rsp), %xmm3
    movshdup -200(%rbp), %xmm8
    movshdup (%r12), %xmm7
    movshdup 0x40(%r13), %xmm11
    movshdup (%rax,%r9,8), %xmm1
    movshdup 16(%r15,%rcx,2), %xmm14
    movshdup -4(%rdx,%r14,4), %xmm3
    movsldup %xmm3, %xmm0
    movsldup %xmm15, %xmm2
    movsldup %xmm1, %xmm14
    movsldup %xmm12, %xmm8
    movsldup (%rax), %xmm14
    movsldup 8(%rsp), %xmm3
    movsldup -200(%rbp), %xmm8
    movsldup (%r12), %xmm7
    movsldup 0x40(%r13), %xmm11
    movsldup (%rax,%r9,8), %xmm1
    movsldup 16(%r15,%rcx,2), %xmm14
    movsldup -4(%rdx,%r14,4), %xmm3
    pshufb %xmm3, %xmm0
    pshufb %xmm15, %xmm2
    pshufb %xmm1, %xmm14
    pshufb %xmm12, %xmm8
    pshufb (%rax), %xmm14
    pshufb 8(%rsp), %xmm3
    pshufb -200(%rbp), %xmm8
    pshufb (%r12), %xmm7
    pshufb 0x40(%r13), %xmm11
    pshufb (%rax,%r9,8), %xmm1
    pshufb 16(%r15,%rcx,2), %xmm14
    pshufb -4(%rdx,%r14,4), %xmm3
    phaddw %xmm3, %xmm0
    phaddw %xmm15, %xmm2
    phaddw %xmm1, %xmm14
    phaddw %xmm12, %xmm8
    phaddw (%rax), %xmm14
    phaddw 8(%rsp), %xmm3
    phaddw -200(%rbp), %xmm8
    phaddw (%r12), %xmm7
    phaddw 0x40(%r13), %xmm11
    phaddw (%rax,%r9,8), %xmm1
    phaddw 16(%r15,%rcx,2), %xmm14
    phaddw -4(%rdx,%r14,4), %xmm3
    phaddd %xmm3, %xmm0
    phaddd %xmm15, %xmm2
    phaddd %xmm1, %xmm14
    phaddd %xmm12, %xmm8
    phaddd (%rax), %xmm14
    phaddd 8(%rsp), %xmm3
    phaddd -200(%rbp), %xmm8
    phaddd (%r12), %xmm7
    phaddd 0x40(%r13), %xmm11
    phaddd (%rax,%r9,8), %xmm1
    phaddd 16(%r15,%rcx,2), %xmm14
    phaddd -4(%rdx,%r14,4), %xmm3
    phaddsw %xmm3, %xmm0
    phaddsw %xmm15, %xmm2
    phaddsw %xmm1, %xmm14
    phaddsw %xmm12, %xmm8
    phaddsw (%rax), %xmm14
    phaddsw 8(%rsp), %xmm3
    phaddsw -200(%rbp), %xmm8
    phaddsw (%r12), %xmm7
    phaddsw 0x40(%r13), %xmm11
    phaddsw (%rax,%r9,8), %xmm1
    phaddsw 16(%r15,%rcx,2), %xmm14
    phaddsw -4(%rdx,%r14,4), %xmm3
    pmaddubsw %xmm3, %xmm0
    pmaddubsw %xmm15, %xmm2
    pmaddubsw %xmm1, %xmm14
    pmaddubsw %xmm12, %xmm8
    pmaddubsw (%rax), %xmm14
    pmaddubsw 8(%rsp), %xmm3
    pmaddubsw -200(%rbp), %xmm8
    pmaddubsw (%r12), %xmm7
    pmaddubsw 0x40(%r13), %xmm11
    pmaddubsw (%rax,%r9,8), %xmm1
    pmaddubsw 16(%r15,%rcx,2), %xmm14
    pmaddubsw -4(%rdx,%r14,4), %xmm3
    phsubw %xmm3, %xmm0
    phsubw %xmm15, %xmm2
    phsubw %xmm1, %xmm14
    phsubw %xmm12, %xmm8
    phsubw (%rax), %xmm14
    phsubw 8(%rsp), %xmm3
    phsubw -200(%rbp), %xmm8
    phsubw (%r12), %xmm7
    phsubw 0x40(%r13), %xmm11
    phsubw (%rax,%r9,8), %xmm1
    phsubw 16(%r15,%rcx,2), %xmm14
    phsubw -4(%rdx,%r14,4), %xmm3
    phsubd %xmm3, %xmm0
    phsubd %xmm15, %xmm2
    phsubd %xmm1, %xmm14
    phsubd %xmm12, %xmm8
    phsubd (%rax), %xmm14
    phsubd 8(%rsp), %xmm3
    phsubd -200(%rbp), %xmm8
    phsubd (%r12), %xmm7
    phsubd 0x40(%r13), %xmm11
    phsubd (%rax,%r9,8), %xmm1
    phsubd 16(%r15,%rcx,2), %xmm14
    phsubd -4(%rdx,%r14,4), %xmm3
    phsubsw %xmm3, %xmm0
    phsubsw %xmm15, %xmm2
    phsubsw %xmm1, %xmm14
    phsubsw %xmm12, %xmm8
    phsubsw (%rax), %xmm14
    phsubsw 8(%rsp), %xmm3
    phsubsw -200(%rbp), %xmm8
    phsubsw (%r12), %xmm7
    phsubsw 0x40(%r13), %xmm11
    phsubsw (%rax,%r9,8), %xmm1
    phsubsw 16(%r15,%rcx,2), %xmm14
    phsubsw -4(%rdx,%r14,4), %xmm3
    psignb %xmm3, %xmm0
    psignb %xmm15, %xmm2
    psignb %xmm1, %xmm14
    psignb %xmm12, %xmm8
    psignb (%rax), %xmm14
    psignb 8(%rsp), %xmm3
    psignb -200(%rbp), %xmm8
    psignb (%r12), %xmm7
    psignb 0x40(%r13), %xmm11
    psignb (%rax,%r9,8), %xmm1
    psignb 16(%r15,%rcx,2), %xmm14
    psignb -4(%rdx,%r14,4), %xmm3
    psignw %xmm3, %xmm0
    psignw %xmm15, %xmm2
    psignw %xmm1, %xmm14
    psignw %xmm12, %xmm8
    psignw (%rax), %xmm14
    psignw 8(%rsp), %xmm3
    psignw -200(%rbp), %xmm8
    psignw (%r12), %xmm7
    psignw 0x40(%r13), %xmm11
    psignw (%rax,%r9,8), %xmm1
    psignw 16(%r15,%rcx,2), %xmm14
    psignw -4(%rdx,%r14,4), %xmm3
    psignd %xmm3, %xmm0
    psignd %xmm15, %xmm2
    psignd %xmm1, %xmm14
    psignd %xmm12, %xmm8
    psignd (%rax), %xmm14
    psignd 8(%rsp), %xmm3
    psignd -200(%rbp), %xmm8
    psignd (%r12), %xmm7
    psignd 0x40(%r13), %xmm11
    psignd (%rax,%r9,8), %xmm1
    psignd 16(%r15,%rcx,2), %xmm14
    psignd -4(%rdx,%r14,4), %xmm3
    pmulhrsw %xmm3, %xmm0
    pmulhrsw %xmm15, %xmm2
    pmulhrsw %xmm1, %xmm14
    pmulhrsw %xmm12, %xmm8
    pmulhrsw (%rax), %xmm14
    pmulhrsw 8(%rsp), %xmm3
    pmulhrsw -200(%rbp), %xmm8
    pmulhrsw (%r12), %xmm7
    pmulhrsw 0x40(%r13), %xmm11
    pmulhrsw (%rax,%r9,8), %xmm1
    pmulhrsw 16(%r15,%rcx,2), %xmm14
    pmulhrsw -4(%rdx,%r14,4), %xmm3
    pabsb %xmm3, %xmm0
    pabsb %xmm15, %xmm2
    pabsb %xmm1, %xmm14
    pabsb %xmm12, %xmm8
    pabsb (%rax), %xmm14
    pabsb 8(%rsp), %xmm3
    pabsb -200(%rbp), %xmm8
    pabsb (%r12), %xmm7
    pabsb 0x40(%r13), %xmm11
    pabsb (%rax,%r9,8), %xmm1
    pabsb 16(%r15,%rcx,2), %xmm14
    pabsb -4(%rdx,%r14,4), %xmm3
    pabsw %xmm3, %xmm0
    pabsw %xmm15, %xmm2
    pabsw %xmm1, %xmm14
    pabsw %xmm12, %xmm8
    pabsw (%rax), %xmm14
    pabsw 8(%rsp), %xmm3
    pabsw -200(%rbp), %xmm8
    pabsw (%r12), %xmm7
    pabsw 0x40(%r13), %xmm11
    pabsw (%rax,%r9,8), %xmm1
    pabsw 16(%r15,%rcx,2), %xmm14
    pabsw -4(%rdx,%r14,4), %xmm3
    pabsd %xmm3, %xmm0
    pabsd %xmm15, %xmm2
    pabsd %xmm1, %xmm14
    pabsd %xmm12, %xmm8
    pabsd (%rax), %xmm14
    pabsd 8(%rsp), %xmm3
    pabsd -200(%rbp), %xmm8
    pabsd (%r12), %xmm7
    pabsd 0x40(%r13), %xmm11
    pabsd (%rax,%r9,8), %xmm1
    pabsd 16(%r15,%rcx,2), %xmm14
    pabsd -4(%rdx,%r14,4), %xmm3
    palignr $0x7f, %xmm3, %xmm0
    palignr $0xff, %xmm15, %xmm2
    palignr $0, %xmm1, %xmm14
    palignr $0x7f, %xmm12, %xmm8
    palignr $0, (%rax), %xmm3
    palignr $0x7f, 8(%rsp), %xmm8
    palignr $0xff, -200(%rbp), %xmm7
    palignr $0, (%r12), %xmm11
    palignr $0x7f, 0x40(%r13), %xmm1
    palignr $0xff, (%rax,%r9,8), %xmm14
    palignr $0, 16(%r15,%rcx,2), %xmm3
    palignr $0x7f, -4(%rdx,%r14,4), %xmm8
    ptest %xmm3, %xmm0
    ptest %xmm15, %xmm2
    ptest %xmm1, %xmm14
    ptest %xmm12, %xmm8
    ptest (%rax), %xmm14
    ptest 8(%rsp), %xmm3
    ptest -200(%rbp), %xmm8
    ptest (%r12), %xmm7
    ptest 0x40(%r13), %xmm11
    ptest (%rax,%r9,8), %xmm1
    ptest 16(%r15,%rcx,2), %xmm14
    ptest -4(%rdx,%r14,4), %xmm3
    pmuldq %xmm3, %xmm0
    pmuldq %xmm15, %xmm2
    pmuldq %xmm1, %xmm14
    pmuldq %xmm12, %xmm8
    pmuldq (%rax), %xmm14
    pmuldq 8(%rsp), %xmm3
    pmuldq -200(%rbp), %xmm8
    pmuldq (%r12), %xmm7
    pmuldq 0x40(%r13), %xmm11
    pmuldq (%rax,%r9,8), %xmm1
    pmuldq 16(%r15,%rcx,2), %xmm14
    pmuldq -4(%rdx,%r14,4), %xmm3
    pcmpeqq %xmm3, %xmm0
    pcmpeqq %xmm15, %xmm2
    pcmpeqq %xmm1, %xmm14
    pcmpeqq %xmm12, %xmm8
    pcmpeqq (%rax), %xmm14
    pcmpeqq 8(%rsp), %xmm3
    pcmpeqq -200(%rbp), %xmm8
    pcmpeqq (%r12), %xmm7
    pcmpeqq 0x40(%r13), %xmm11
    pcmpeqq (%rax,%r9,8), %xmm1
    pcmpeqq 16(%r15,%rcx,2), %xmm14
    pcmpeqq -4(%rdx,%r14,4), %xmm3
    packusdw %xmm3, %xmm0
    packusdw %xmm15, %xmm2
    packusdw %xmm1, %xmm14
    packusdw %xmm12, %xmm8
    packusdw (%rax), %xmm14
    packusdw 8(%rsp), %xmm3
    packusdw -200(%rbp), %xmm8
    packusdw (%r12), %xmm7
    packusdw 0x40(%r13), %xmm11
    packusdw (%rax,%r9,8), %xmm1
    packusdw 16(%r15,%rcx,2), %xmm14
    packusdw -4(%rdx,%r14,4), %xmm3
    pminsb %xmm3, %xmm0
    pminsb %xmm15, %xmm2
    pminsb %xmm1, %xmm14
    pminsb %xmm12, %xmm8
    pminsb (%rax), %xmm14
    pminsb 8(%rsp), %xmm3
    pminsb -200(%rbp), %xmm8
    pminsb (%r12), %xmm7
    pminsb 0x40(%r13), %xmm11
    pminsb (%rax,%r9,8), %xmm1
    pminsb 16(%r15,%rcx,2), %xmm14
    pminsb -4(%rdx,%r14,4), %xmm3
    pminsd %xmm3, %xmm0
    pminsd %xmm15, %xmm2
    pminsd %xmm1, %xmm14
    pminsd %xmm12, %xmm8
    pminsd (%rax), %xmm14
    pminsd 8(%rsp), %xmm3
    pminsd -200(%rbp), %xmm8
    pminsd (%r12), %xmm7
    pminsd 0x40(%r13), %xmm11
    pminsd (%rax,%r9,8), %xmm1
    pminsd 16(%r15,%rcx,2), %xmm14
    pminsd -4(%rdx,%r14,4), %xmm3
    pminuw %xmm3, %xmm0
    pminuw %xmm15, %xmm2
    pminuw %xmm1, %xmm14
    pminuw %xmm12, %xmm8
    pminuw (%rax), %xmm14
    pminuw 8(%rsp), %xmm3
    pminuw -200(%rbp), %xmm8
    pminuw (%r12), %xmm7
    pminuw 0x40(%r13), %xmm11
    pminuw (%rax,%r9,8), %xmm1
    pminuw 16(%r15,%rcx,2), %xmm14
    pminuw -4(%rdx,%r14,4), %xmm3
    pminud %xmm3, %xmm0
    pminud %xmm15, %xmm2
    pminud %xmm1, %xmm14
    pminud %xmm12, %xmm8
    pminud (%rax), %xmm14
    pminud 8(%rsp), %xmm3
    pminud -200(%rbp), %xmm8
    pminud (%r12), %xmm7
    pminud 0x40(%r13), %xmm11
    pminud (%rax,%r9,8), %xmm1
    pminud 16(%r15,%rcx,2), %xmm14
    pminud -4(%rdx,%r14,4), %xmm3
    pmaxsb %xmm3, %xmm0
    pmaxsb %xmm15, %xmm2
    pmaxsb %xmm1, %xmm14
    pmaxsb %xmm12, %xmm8
    pmaxsb (%rax), %xmm14
    pmaxsb 8(%rsp), %xmm3
    pmaxsb -200(%rbp), %xmm8
    pmaxsb (%r12), %xmm7
    pmaxsb 0x40(%r13), %xmm11
    pmaxsb (%rax,%r9,8), %xmm1
    pmaxsb 16(%r15,%rcx,2), %xmm14
    pmaxsb -4(%rdx,%r14,4), %xmm3
    pmaxsd %xmm3, %xmm0
    pmaxsd %xmm15, %xmm2
    pmaxsd %xmm1, %xmm14
    pmaxsd %xmm12, %xmm8
    pmaxsd (%rax), %xmm14
    pmaxsd 8(%rsp), %xmm3
    pmaxsd -200(%rbp), %xmm8
    pmaxsd (%r12), %xmm7
    pmaxsd 0x40(%r13), %xmm11
    pmaxsd (%rax,%r9,8), %xmm1
    pmaxsd 16(%r15,%rcx,2), %xmm14
    pmaxsd -4(%rdx,%r14,4), %xmm3
    pmaxuw %xmm3, %xmm0
    pmaxuw %xmm15, %xmm2
    pmaxuw %xmm1, %xmm14
    pmaxuw %xmm12, %xmm8
    pmaxuw (%rax), %xmm14
    pmaxuw 8(%rsp), %xmm3
    pmaxuw -200(%rbp), %xmm8
    pmaxuw (%r12), %xmm7
    pmaxuw 0x40(%r13), %xmm11
    pmaxuw (%rax,%r9,8), %xmm1
    pmaxuw 16(%r15,%rcx,2), %xmm14
    pmaxuw -4(%rdx,%r14,4), %xmm3
    pmaxud %xmm3, %xmm0
    pmaxud %xmm15, %xmm2
    pmaxud %xmm1, %xmm14
    pmaxud %xmm12, %xmm8
    pmaxud (%rax), %xmm14
    pmaxud 8(%rsp), %xmm3
    pmaxud -200(%rbp), %xmm8
    pmaxud (%r12), %xmm7
    pmaxud 0x40(%r13), %xmm11
    pmaxud (%rax,%r9,8), %xmm1
    pmaxud 16(%r15,%rcx,2), %xmm14
    pmaxud -4(%rdx,%r14,4), %xmm3
    pmulld %xmm3, %xmm0
    pmulld %xmm15, %xmm2
    pmulld %xmm1, %xmm14
    pmulld %xmm12, %xmm8
    pmulld (%rax), %xmm14
    pmulld 8(%rsp), %xmm3
    pmulld -200(%rbp), %xmm8
    pmulld (%r12), %xmm7
    pmulld 0x40(%r13), %xmm11
    pmulld (%rax,%r9,8), %xmm1
    pmulld 16(%r15,%rcx,2), %xmm14
    pmulld -4(%rdx,%r14,4), %xmm3
    phminposuw %xmm3, %xmm0
    phminposuw %xmm15, %xmm2
    phminposuw %xmm1, %xmm14
    phminposuw %xmm12, %xmm8
    phminposuw (%rax), %xmm14
    phminposuw 8(%rsp), %xmm3
    phminposuw -200(%rbp), %xmm8
    phminposuw (%r12), %xmm7
    phminposuw 0x40(%r13), %xmm11
    phminposuw (%rax,%r9,8), %xmm1
    phminposuw 16(%r15,%rcx,2), %xmm14
    phminposuw -4(%rdx,%r14,4), %xmm3
    pmovsxbw %xmm3, %xmm0
    pmovsxbw %xmm15, %xmm2
    pmovsxbw %xmm1, %xmm14
    pmovsxbw %xmm12, %xmm8
    pmovsxbw (%rax), %xmm14
    pmovsxbw 8(%rsp), %xmm3
    pmovsxbw -200(%rbp), %xmm8
    pmovsxbw (%r12), %xmm7
    pmovsxbw 0x40(%r13), %xmm11
    pmovsxbw (%rax,%r9,8), %xmm1
    pmovsxbw 16(%r15,%rcx,2), %xmm14
    pmovsxbw -4(%rdx,%r14,4), %xmm3
    pmovsxbd %xmm3, %xmm0
    pmovsxbd %xmm15, %xmm2
    pmovsxbd %xmm1, %xmm14
    pmovsxbd %xmm12, %xmm8
    pmovsxbd (%rax), %xmm14
    pmovsxbd 8(%rsp), %xmm3
    pmovsxbd -200(%rbp), %xmm8
    pmovsxbd (%r12), %xmm7
    pmovsxbd 0x40(%r13), %xmm11
    pmovsxbd (%rax,%r9,8), %xmm1
    pmovsxbd 16(%r15,%rcx,2), %xmm14
    pmovsxbd -4(%rdx,%r14,4), %xmm3
    pmovsxbq %xmm3, %xmm0
    pmovsxbq %xmm15, %xmm2
    pmovsxbq %xmm1, %xmm14
    pmovsxbq %xmm12, %xmm8
    pmovsxbq (%rax), %xmm14
    pmovsxbq 8(%rsp), %xmm3
    pmovsxbq -200(%rbp), %xmm8
    pmovsxbq (%r12), %xmm7
    pmovsxbq 0x40(%r13), %xmm11
    pmovsxbq (%rax,%r9,8), %xmm1
    pmovsxbq 16(%r15,%rcx,2), %xmm14
    pmovsxbq -4(%rdx,%r14,4), %xmm3
    pmovsxwd %xmm3, %xmm0
    pmovsxwd %xmm15, %xmm2
    pmovsxwd %xmm1, %xmm14
    pmovsxwd %xmm12, %xmm8
    pmovsxwd (%rax), %xmm14
    pmovsxwd 8(%rsp), %xmm3
    pmovsxwd -200(%rbp), %xmm8
    pmovsxwd (%r12), %xmm7
    pmovsxwd 0x40(%r13), %xmm11
    pmovsxwd (%rax,%r9,8), %xmm1
    pmovsxwd 16(%r15,%rcx,2), %xmm14
    pmovsxwd -4(%rdx,%r14,4), %xmm3
    pmovsxwq %xmm3, %xmm0
    pmovsxwq %xmm15, %xmm2
    pmovsxwq %xmm1, %xmm14
    pmovsxwq %xmm12, %xmm8
    pmovsxwq (%rax), %xmm14
    pmovsxwq 8(%rsp), %xmm3
    pmovsxwq -200(%rbp), %xmm8
    pmovsxwq (%r12), %xmm7
    pmovsxwq 0x40(%r13), %xmm11
    pmovsxwq (%rax,%r9,8), %xmm1
    pmovsxwq 16(%r15,%rcx,2), %xmm14
    pmovsxwq -4(%rdx,%r14,4), %xmm3
    pmovsxdq %xmm3, %xmm0
    pmovsxdq %xmm15, %xmm2
    pmovsxdq %xmm1, %xmm14
    pmovsxdq %xmm12, %xmm8
    pmovsxdq (%rax), %xmm14
    pmovsxdq 8(%rsp), %xmm3
    pmovsxdq -200(%rbp), %xmm8
    pmovsxdq (%r12), %xmm7
    pmovsxdq 0x40(%r13), %xmm11
    pmovsxdq (%rax,%r9,8), %xmm1
    pmovsxdq 16(%r15,%rcx,2), %xmm14
    pmovsxdq -4(%rdx,%r14,4), %xmm3
    pmovzxbw %xmm3, %xmm0
    pmovzxbw %xmm15, %xmm2
    pmovzxbw %xmm1, %xmm14
    pmovzxbw %xmm12, %xmm8
    pmovzxbw (%rax), %xmm14
    pmovzxbw 8(%rsp), %xmm3
    pmovzxbw -200(%rbp), %xmm8
    pmovzxbw (%r12), %xmm7
    pmovzxbw 0x40(%r13), %xmm11
    pmovzxbw (%rax,%r9,8), %xmm1
    pmovzxbw 16(%r15,%rcx,2), %xmm14
    pmovzxbw -4(%rdx,%r14,4), %xmm3
    pmovzxbd %xmm3, %xmm0
    pmovzxbd %xmm15, %xmm2
    pmovzxbd %xmm1, %xmm14
    pmovzxbd %xmm12, %xmm8
    pmovzxbd (%rax), %xmm14
    pmovzxbd 8(%rsp), %xmm3
    pmovzxbd -200(%rbp), %xmm8
    pmovzxbd (%r12), %xmm7
    pmovzxbd 0x40(%r13), %xmm11
    pmovzxbd (%rax,%r9,8), %xmm1
    pmovzxbd 16(%r15,%rcx,2), %xmm14
    pmovzxbd -4(%rdx,%r14,4), %xmm3
    pmovzxbq %xmm3, %xmm0
    pmovzxbq %xmm15, %xmm2
    pmovzxbq %xmm1, %xmm14
    pmovzxbq %xmm12, %xmm8
    pmovzxbq (%rax), %xmm14
    pmovzxbq 8(%rsp), %xmm3
    pmovzxbq -200(%rbp), %xmm8
    pmovzxbq (%r12), %xmm7
    pmovzxbq 0x40(%r13), %xmm11
    pmovzxbq (%rax,%r9,8), %xmm1
    pmovzxbq 16(%r15,%rcx,2), %xmm14
    pmovzxbq -4(%rdx,%r14,4), %xmm3
    pmovzxwd %xmm3, %xmm0
    pmovzxwd %xmm15, %xmm2
    pmovzxwd %xmm1, %xmm14
    pmovzxwd %xmm12, %xmm8
    pmovzxwd (%rax), %xmm14
    pmovzxwd 8(%rsp), %xmm3
    pmovzxwd -200(%rbp), %xmm8
    pmovzxwd (%r12), %xmm7
    pmovzxwd 0x40(%r13), %xmm11
    pmovzxwd (%rax,%r9,8), %xmm1
    pmovzxwd 16(%r15,%rcx,2), %xmm14
    pmovzxwd -4(%rdx,%r14,4), %xmm3
    pmovzxwq %xmm3, %xmm0
    pmovzxwq %xmm15, %xmm2
    pmovzxwq %xmm1, %xmm14
    pmovzxwq %xmm12, %xmm8
    pmovzxwq (%rax), %xmm14
    pmovzxwq 8(%rsp), %xmm3
    pmovzxwq -200(%rbp), %xmm8
    pmovzxwq (%r12), %xmm7
    pmovzxwq 0x40(%r13), %xmm11
    pmovzxwq (%rax,%r9,8), %xmm1
    pmovzxwq 16(%r15,%rcx,2), %xmm14
    pmovzxwq -4(%rdx,%r14,4), %xmm3
    pmovzxdq %xmm3, %xmm0
    pmovzxdq %xmm15, %xmm2
    pmovzxdq %xmm1, %xmm14
    pmovzxdq %xmm12, %xmm8
    pmovzxdq (%rax), %xmm14
    pmovzxdq 8(%rsp), %xmm3
    pmovzxdq -200(%rbp), %xmm8
    pmovzxdq (%r12), %xmm7
    pmovzxdq 0x40(%r13), %xmm11
    pmovzxdq (%rax,%r9,8), %xmm1
    pmovzxdq 16(%r15,%rcx,2), %xmm14
    pmovzxdq -4(%rdx,%r14,4), %xmm3
    pblendvb %xmm0, %xmm3, %xmm0
    pblendvb %xmm0, %xmm15, %xmm2
    pblendvb %xmm0, %xmm1, %xmm14
    pblendvb %xmm0, %xmm12, %xmm8
    pblendvb %xmm0, (%rax), %xmm3
    pblendvb %xmm0, 8(%rsp), %xmm8
    pblendvb %xmm0, -200(%rbp), %xmm7
    pblendvb %xmm0, (%r12), %xmm11
    pblendvb %xmm0, 0x40(%r13), %xmm1
    pblendvb %xmm0, (%rax,%r9,8), %xmm14
    pblendvb %xmm0, 16(%r15,%rcx,2), %xmm3
    pblendvb %xmm0, -4(%rdx,%r14,4), %xmm8
    blendvps %xmm0, %xmm3, %xmm0
    blendvps %xmm0, %xmm15, %xmm2
    blendvps %xmm0, %xmm1, %xmm14
    blendvps %xmm0, %xmm12, %xmm8
    blendvps %xmm0, (%rax), %xmm3
    blendvps %xmm0, 8(%rsp), %xmm8
    blendvps %xmm0, -200(%rbp), %xmm7
    blendvps %xmm0, (%r12), %xmm11
    blendvps %xmm0, 0x40(%r13), %xmm1
    blendvps %xmm0, (%rax,%r9,8), %xmm14
    blendvps %xmm0, 16(%r15,%rcx,2), %xmm3
    blendvps %xmm0, -4(%rdx,%r14,4), %xmm8
    blendvpd %xmm0, %xmm3, %xmm0
    blendvpd %xmm0, %xmm15, %xmm2
    blendvpd %xmm0, %xmm1, %xmm14
    blendvpd %xmm0, %xmm12, %xmm8
    blendvpd %xmm0, (%rax), %xmm3
    blendvpd %xmm0, 8(%rsp), %xmm8
    blendvpd %xmm0, -200(%rbp), %xmm7
    blendvpd %xmm0, (%r12), %xmm11
    blendvpd %xmm0, 0x40(%r13), %xmm1
    blendvpd %xmm0, (%rax,%r9,8), %xmm14
    blendvpd %xmm0, 16(%r15,%rcx,2), %xmm3
    blendvpd %xmm0, -4(%rdx,%r14,4), %xmm8
    roundps $0x7f, %xmm3, %xmm0
    roundps $0xff, %xmm15, %xmm2
    roundps $0, %xmm1, %xmm14
    roundps $0x7f, %xmm12, %xmm8
    roundps $0, (%rax), %xmm3
    roundps $0x7f, 8(%rsp), %xmm8
    roundps $0xff, -200(%rbp), %xmm7
    roundps $0, (%r12), %xmm11
    roundps $0x7f, 0x40(%r13), %xmm1
    roundps $0xff, (%rax,%r9,8), %xmm14
    roundps $0, 16(%r15,%rcx,2), %xmm3
    roundps $0x7f, -4(%rdx,%r14,4), %xmm8
    roundpd $0x7f, %xmm3, %xmm0
    roundpd $0xff, %xmm15, %xmm2
    roundpd $0, %xmm1, %xmm14
    roundpd $0x7f, %xmm12, %xmm8
    roundpd $0, (%rax), %xmm3
    roundpd $0x7f, 8(%rsp), %xmm8
    roundpd $0xff, -200(%rbp), %xmm7
    roundpd $0, (%r12), %xmm11
    roundpd $0x7f, 0x40(%r13), %xmm1
    roundpd $0xff, (%rax,%r9,8), %xmm14
    roundpd $0, 16(%r15,%rcx,2), %xmm3
    roundpd $0x7f, -4(%rdx,%r14,4), %xmm8
    blendps $0x7f, %xmm3, %xmm0
    blendps $0xff, %xmm15, %xmm2
    blendps $0, %xmm1, %xmm14
    blendps $0x7f, %xmm12, %xmm8
    blendps $0, (%rax), %xmm3
    blendps $0x7f, 8(%rsp), %xmm8
    blendps $0xff, -200(%rbp), %xmm7
    blendps $0, (%r12), %xmm11
    blendps $0x7f, 0x40(%r13), %xmm1
    blendps $0xff, (%rax,%r9,8), %xmm14
    blendps $0, 16(%r15,%rcx,2), %xmm3
    blendps $0x7f, -4(%rdx,%r14,4), %xmm8
    blendpd $0x7f, %xmm3, %xmm0
    blendpd $0xff, %xmm15, %xmm2
    blendpd $0, %xmm1, %xmm14
    blendpd $0x7f, %xmm12, %xmm8
    blendpd $0, (%rax), %xmm3
    blendpd $0x7f, 8(%rsp), %xmm8
    blendpd $0xff, -200(%rbp), %xmm7
    blendpd $0, (%r12), %xmm11
    blendpd $0x7f, 0x40(%r13), %xmm1
    blendpd $0xff, (%rax,%r9,8), %xmm14
    blendpd $0, 16(%r15,%rcx,2), %xmm3
    blendpd $0x7f, -4(%rdx,%r14,4), %xmm8
    pblendw $0x7f, %xmm3, %xmm0
    pblendw $0xff, %xmm15, %xmm2
    pblendw $0, %xmm1, %xmm14
    pblendw $0x7f, %xmm12, %xmm8
    pblendw $0, (%rax), %xmm3
    pblendw $0x7f, 8(%rsp), %xmm8
    pblendw $0xff, -200(%rbp), %xmm7
    pblendw $0, (%r12), %xmm11
    pblendw $0x7f, 0x40(%r13), %xmm1
    pblendw $0xff, (%rax,%r9,8), %xmm14
    pblendw $0, 16(%r15,%rcx,2), %xmm3
    pblendw $0x7f, -4(%rdx,%r14,4), %xmm8
    pextrb $0x7f, %xmm3, %eax
    pextrb $0xff, %xmm15, %edx
    pextrb $0, %xmm1, %r14d
    pextrb $0x7f, %xmm12, %r8d
    pextrd $0, %xmm1, %esi
    pextrd $0x7f, %xmm12, %eax
    pextrd $0xff, %xmm7, %r11d
    pextrd $0, %xmm9, %r14d
    pextrd $0xff, %xmm14, (%rax)
    pextrd $0, %xmm3, 8(%rsp)
    pextrd $0x7f, %xmm8, -200(%rbp)
    pextrd $0xff, %xmm7, (%r12)
    pextrd $0, %xmm11, 0x40(%r13)
    pextrd $0x7f, %xmm1, (%rax,%r9,8)
    pextrd $0xff, %xmm14, 16(%r15,%rcx,2)
    pextrd $0, %xmm3, -4(%rdx,%r14,4)
    pextrq $0, %xmm1, %rsi
    pextrq $0x7f, %xmm12, %rax
    pextrq $0xff, %xmm7, %r11
    pextrq $0, %xmm9, %r14
    pextrq $0xff, %xmm14, (%rax)
    pextrq $0, %xmm3, 8(%rsp)
    pextrq $0x7f, %xmm8, -200(%rbp)
    pextrq $0xff, %xmm7, (%r12)
    pextrq $0, %xmm11, 0x40(%r13)
    pextrq $0x7f, %xmm1, (%rax,%r9,8)
    pextrq $0xff, %xmm14, 16(%r15,%rcx,2)
    pextrq $0, %xmm3, -4(%rdx,%r14,4)
    extractps $0, %xmm1, %esi
    extractps $0x7f, %xmm12, %eax
    extractps $0xff, %xmm7, %r11d
    extractps $0, %xmm9, %r14d
    extractps $0xff, %xmm14, (%rax)
    extractps $0, %xmm3, 8(%rsp)
    extractps $0x7f, %xmm8, -200(%rbp)
    extractps $0xff, %xmm7, (%r12)
    extractps $0, %xmm11, 0x40(%r13)
    extractps $0x7f, %xmm1, (%rax,%r9,8)
    extractps $0xff, %xmm14, 16(%r15,%rcx,2)
    extractps $0, %xmm3, -4(%rdx,%r14,4)
    pinsrb $0, %ecx, %xmm6
    pinsrb $0x7f, %r12d, %xmm0
    pinsrb $0xff, %edi, %xmm11
    pinsrb $0, %r9d, %xmm14
    pinsrd $0xff, %edi, %xmm2
    pinsrd $0, %r9d, %xmm6
    pinsrd $0x7f, %ebx, %xmm8
    pinsrd $0xff, %r15d, %xmm11
    pinsrd $0x7f, (%rax), %xmm3
    pinsrd $0xff, 8(%rsp), %xmm8
    pinsrd $0, -200(%rbp), %xmm7
    pinsrd $0x7f, (%r12), %xmm11
    pinsrd $0xff, 0x40(%r13), %xmm1
    pinsrd $0, (%rax,%r9,8), %xmm14
    pinsrd $0x7f, 16(%r15,%rcx,2), %xmm3
    pinsrd $0xff, -4(%rdx,%r14,4), %xmm8
    pinsrq $0xff, %rdi, %xmm2
    pinsrq $0, %r9, %xmm6
    pinsrq $0x7f, %rbx, %xmm8
    pinsrq $0xff, %r15, %xmm11
    pinsrq $0x7f, (%rax), %xmm3
    pinsrq $0xff, 8(%rsp), %xmm8
    pinsrq $0, -200(%rbp), %xmm7
    pinsrq $0x7f, (%r12), %xmm11
    pinsrq $0xff, 0x40(%r13), %xmm1
    pinsrq $0, (%rax,%r9,8), %xmm14
    pinsrq $0x7f, 16(%r15,%rcx,2), %xmm3
    pinsrq $0xff, -4(%rdx,%r14,4), %xmm8
    pcmpgtq %xmm7, %xmm2
    pcmpgtq %xmm9, %xmm6
    pcmpgtq %xmm3, %xmm8
    pcmpgtq %xmm15, %xmm11
    pcmpgtq (%rax), %xmm14
    pcmpgtq 8(%rsp), %xmm3
    pcmpgtq -200(%rbp), %xmm8
    pcmpgtq (%r12), %xmm7
    pcmpgtq 0x40(%r13), %xmm11
    pcmpgtq (%rax,%r9,8), %xmm1
    pcmpgtq 16(%r15,%rcx,2), %xmm14
    pcmpgtq -4(%rdx,%r14,4), %xmm3
    crc32b %dil, %edx
    crc32b %r9b, %esi
    crc32b %bl, %r8d
    crc32b %r15b, %r11d
    crc32b (%rax), %r14d
    crc32b 8(%rsp), %ebx
    crc32b -200(%rbp), %r8d
    crc32b (%r12), %edi
    crc32b 0x40(%r13), %r11d
    crc32b (%rax,%r9,8), %ecx
    crc32b 16(%r15,%rcx,2), %r14d
    crc32b -4(%rdx,%r14,4), %ebx
    crc32w %di, %edx
    crc32w %r9w, %esi
    crc32w %bx, %r8d
    crc32w %r15w, %r11d
    crc32w (%rax), %r14d
    crc32w 8(%rsp), %ebx
    crc32w -200(%rbp), %r8d
    crc32w (%r12), %edi
    crc32w 0x40(%r13), %r11d
    crc32w (%rax,%r9,8), %ecx
    crc32w 16(%r15,%rcx,2), %r14d
    crc32w -4(%rdx,%r14,4), %ebx
    crc32l %edi, %edx
    crc32l %r9d, %esi
    crc32l %ebx, %r8d
    crc32l %r15d, %r11d
    crc32l (%rax), %r14d
    crc32l 8(%rsp), %ebx
    crc32l -200(%rbp), %r8d
    crc32l (%r12), %edi
    crc32l 0x40(%r13), %r11d
    crc32l (%rax,%r9,8), %ecx
    crc32l 16(%r15,%rcx,2), %r14d
    crc32l -4(%rdx,%r14,4), %ebx
    crc32q %rdi, %rdx
    crc32q %r9, %rsi
    crc32q %rbx, %r8
    crc32q %r15, %r11
    crc32q (%rax), %r14
    crc32q 8(%rsp), %rbx
    crc32q -200(%rbp), %r8
    crc32q (%r12), %rdi
    crc32q 0x40(%r13), %r11
    crc32q (%rax,%r9,8), %rcx
    crc32q 16(%r15,%rcx,2), %r14
    crc32q -4(%rdx,%r14,4), %rbx
    popcntl %edi, %edx
    popcntl %r9d, %esi
    popcntl %ebx, %r8d
    popcntl %r15d, %r11d
    popcntl (%rax), %r14d
    popcntl 8(%rsp), %ebx
    popcntl -200(%rbp), %r8d
    popcntl (%r12), %edi
    popcntl 0x40(%r13), %r11d
    popcntl (%rax,%r9,8), %ecx
    popcntl 16(%r15,%rcx,2), %r14d
    popcntl -4(%rdx,%r14,4), %ebx
    popcntq %rdi, %rdx
    popcntq %r9, %rsi
    popcntq %rbx, %r8
    popcntq %r15, %r11
    popcntq (%rax), %r14
    popcntq 8(%rsp), %rbx
    popcntq -200(%rbp), %r8
    popcntq (%r12), %rdi
    popcntq 0x40(%r13), %r11
    popcntq (%rax,%r9,8), %rcx
    popcntq 16(%r15,%rcx,2), %r14
    popcntq -4(%rdx,%r14,4), %rbx
    lzcntl %edi, %edx
    lzcntl %r9d, %esi
    lzcntl %ebx, %r8d
    lzcntl %r15d, %r11d
    lzcntl (%rax), %r14d
    lzcntl 8(%rsp), %ebx
    lzcntl -200(%rbp), %r8d
    lzcntl (%r12), %edi
    lzcntl 0x40(%r13), %r11d
    lzcntl (%rax,%r9,8), %ecx
    lzcntl 16(%r15,%rcx,2), %r14d
    lzcntl -4(%rdx,%r14,4), %ebx
    lzcntq %rdi, %rdx
    lzcntq %r9, %rsi
    lzcntq %rbx, %r8
    lzcntq %r15, %r11
    lzcntq (%rax), %r14
    lzcntq 8(%rsp), %rbx
    lzcntq -200(%rbp), %r8
    lzcntq (%r12), %rdi
    lzcntq 0x40(%r13), %r11
    lzcntq (%rax,%r9,8), %rcx
    lzcntq 16(%r15,%rcx,2), %r14
    lzcntq -4(%rdx,%r14,4), %rbx
    tzcntl %edi, %edx
    tzcntl %r9d, %esi
    tzcntl %ebx, %r8d
    tzcntl %r15d, %r11d
    tzcntl (%rax), %r14d
    tzcntl 8(%rsp), %ebx
    tzcntl -200(%rbp), %r8d
    tzcntl (%r12), %edi
    tzcntl 0x40(%r13), %r11d
    tzcntl (%rax,%r9,8), %ecx
    tzcntl 16(%r15,%rcx,2), %r14d
    tzcntl -4(%rdx,%r14,4), %ebx
    tzcntq %rdi, %rdx
    tzcntq %r9, %rsi
    tzcntq %rbx, %r8
    tzcntq %r15, %r11
    tzcntq (%rax), %r14
    tzcntq 8(%rsp), %rbx
    tzcntq -200(%rbp), %r8
    tzcntq (%r12), %rdi
    tzcntq 0x40(%r13), %r11
    tzcntq (%rax,%r9,8), %rcx
    tzcntq 16(%r15,%rcx,2), %r14
    tzcntq -4(%rdx,%r14,4), %rbx
    pclmulqdq $0xff, %xmm7, %xmm2
    pclmulqdq $0, %xmm9, %xmm6
    pclmulqdq $0x7f, %xmm3, %xmm8
    pclmulqdq $0xff, %xmm15, %xmm11
    pclmulqdq $0x7f, (%rax), %xmm3
    pclmulqdq $0xff, 8(%rsp), %xmm8
    pclmulqdq $0, -200(%rbp), %xmm7
    pclmulqdq $0x7f, (%r12), %xmm11
    pclmulqdq $0xff, 0x40(%r13), %xmm1
    pclmulqdq $0, (%rax,%r9,8), %xmm14
    pclmulqdq $0x7f, 16(%r15,%rcx,2), %xmm3
    pclmulqdq $0xff, -4(%rdx,%r14,4), %xmm8
    aesimc %xmm7, %xmm2
    aesimc %xmm9, %xmm6
    aesimc %xmm3, %xmm8
    aesimc %xmm15, %xmm11
    aesimc (%rax), %xmm14
    aesimc 8(%rsp), %xmm3
    aesimc -200(%rbp), %xmm8
    aesimc (%r12), %xmm7
    aesimc 0x40(%r13), %xmm11
    aesimc (%rax,%r9,8), %xmm1
    aesimc 16(%r15,%rcx,2), %xmm14
    aesimc -4(%rdx,%r14,4), %xmm3
    aesenc %xmm7, %xmm2
    aesenc %xmm9, %xmm6
    aesenc %xmm3, %xmm8
    aesenc %xmm15, %xmm11
    aesenc (%rax), %xmm14
    aesenc 8(%rsp), %xmm3
    aesenc -200(%rbp), %xmm8
    aesenc (%r12), %xmm7
    aesenc 0x40(%r13), %xmm11
    aesenc (%rax,%r9,8), %xmm1
    aesenc 16(%r15,%rcx,2), %xmm14
    aesenc -4(%rdx,%r14,4), %xmm3
    aesenclast %xmm7, %xmm2
    aesenclast %xmm9, %xmm6
    aesenclast %xmm3, %xmm8
    aesenclast %xmm15, %xmm11
    aesenclast (%rax), %xmm14
    aesenclast 8(%rsp), %xmm3
    aesenclast -200(%rbp), %xmm8
    aesenclast (%r12), %xmm7
    aesenclast 0x40(%r13), %xmm11
    aesenclast (%rax,%r9,8), %xmm1
    aesenclast 16(%r15,%rcx,2), %xmm14
    aesenclast -4(%rdx,%r14,4), %xmm3
    aesdec %xmm7, %xmm2
    aesdec %xmm9, %xmm6
    aesdec %xmm3, %xmm8
    aesdec %xmm15, %xmm11
    aesdec (%rax), %xmm14
    aesdec 8(%rsp), %xmm3
    aesdec -200(%rbp), %xmm8
    aesdec (%r12), %xmm7
    aesdec 0x40(%r13), %xmm11
    aesdec (%rax,%r9,8), %xmm1
    aesdec 16(%r15,%rcx,2), %xmm14
    aesdec -4(%rdx,%r14,4), %xmm3
    aesdeclast %xmm7, %xmm2
    aesdeclast %xmm9, %xmm6
    aesdeclast %xmm3, %xmm8
    aesdeclast %xmm15, %xmm11
    aesdeclast (%rax), %xmm14
    aesdeclast 8(%rsp), %xmm3
    aesdeclast -200(%rbp), %xmm8
    aesdeclast (%r12), %xmm7
    aesdeclast 0x40(%r13), %xmm11
    aesdeclast (%rax,%r9,8), %xmm1
    aesdeclast 16(%r15,%rcx,2), %xmm14
    aesdeclast -4(%rdx,%r14,4), %xmm3
    aeskeygenassist $0xff, %xmm7, %xmm2
    aeskeygenassist $0, %xmm9, %xmm6
    aeskeygenassist $0x7f, %xmm3, %xmm8
    aeskeygenassist $0xff, %xmm15, %xmm11
    aeskeygenassist $0x7f, (%rax), %xmm3
    aeskeygenassist $0xff, 8(%rsp), %xmm8
    aeskeygenassist $0, -200(%rbp), %xmm7
    aeskeygenassist $0x7f, (%r12), %xmm11
    aeskeygenassist $0xff, 0x40(%r13), %xmm1
    aeskeygenassist $0, (%rax,%r9,8), %xmm14
    aeskeygenassist $0x7f, 16(%r15,%rcx,2), %xmm3
    aeskeygenassist $0xff, -4(%rdx,%r14,4), %xmm8
    sha1nexte %xmm7, %xmm2
    sha1nexte %xmm9, %xmm6
    sha1nexte %xmm3, %xmm8
    sha1nexte %xmm15, %xmm11
    sha1nexte (%rax), %xmm14
    sha1nexte 8(%rsp), %xmm3
    sha1nexte -200(%rbp), %xmm8
    sha1nexte (%r12), %xmm7
    sha1nexte 0x40(%r13), %xmm11
    sha1nexte (%rax,%r9,8), %xmm1
    sha1nexte 16(%r15,%rcx,2), %xmm14
    sha1nexte -4(%rdx,%r14,4), %xmm3
    sha1msg1 %xmm7, %xmm2
    sha1msg1 %xmm9, %xmm6
    sha1msg1 %xmm3, %xmm8
    sha1msg1 %xmm15, %xmm11
    sha1msg1 (%rax), %xmm14
    sha1msg1 8(%rsp), %xmm3
    sha1msg1 -200(%rbp), %xmm8
    sha1msg1 (%r12), %xmm7
    sha1msg1 0x40(%r13), %xmm11
    sha1msg1 (%rax,%r9,8), %xmm1
    sha1msg1 16(%r15,%rcx,2), %xmm14
    sha1msg1 -4(%rdx,%r14,4), %xmm3
    sha1msg2 %xmm7, %xmm2
    sha1msg2 %xmm9, %xmm6
    sha1msg2 %xmm3, %xmm8
    sha1msg2 %xmm15, %xmm11
    sha1msg2 (%rax), %xmm14
    sha1msg2 8(%rsp), %xmm3
    sha1msg2 -200(%rbp), %xmm8
    sha1msg2 (%r12), %xmm7
    sha1msg2 0x40(%r13), %xmm11
    sha1msg2 (%rax,%r9,8), %xmm1
    sha1msg2 16(%r15,%rcx,2), %xmm14
    sha1msg2 -4(%rdx,%r14,4), %xmm3
    sha256msg1 %xmm7, %xmm2
    sha256msg1 %xmm9, %xmm6
    sha256msg1 %xmm3, %xmm8
    sha256msg1 %xmm15, %xmm11
    sha256msg1 (%rax), %xmm14
    sha256msg1 8(%rsp), %xmm3
    sha256msg1 -200(%rbp), %xmm8
    sha256msg1 (%r12), %xmm7
    sha256msg1 0x40(%r13), %xmm11
    sha256msg1 (%rax,%r9,8), %xmm1
    sha256msg1 16(%r15,%rcx,2), %xmm14
    sha256msg1 -4(%rdx,%r14,4), %xmm3
    sha256msg2 %xmm7, %xmm2
    sha256msg2 %xmm9, %xmm6
    sha256msg2 %xmm3, %xmm8
    sha256msg2 %xmm15, %xmm11
    sha256msg2 (%rax), %xmm14
    sha256msg2 8(%rsp), %xmm3
    sha256msg2 -200(%rbp), %xmm8
    sha256msg2 (%r12), %xmm7
    sha256msg2 0x40(%r13), %xmm11
    sha256msg2 (%rax,%r9,8), %xmm1
    sha256msg2 16(%r15,%rcx,2), %xmm14
    sha256msg2 -4(%rdx,%r14,4), %xmm3
    sha256rnds2 %xmm0, %xmm7, %xmm2
    sha256rnds2 %xmm0, %xmm9, %xmm6
    sha256rnds2 %xmm0, %xmm3, %xmm8
    sha256rnds2 %xmm0, %xmm15, %xmm11
    sha256rnds2 %xmm0, (%rax), %xmm3
    sha256rnds2 %xmm0, 8(%rsp), %xmm8
    sha256rnds2 %xmm0, -200(%rbp), %xmm7
    sha256rnds2 %xmm0, (%r12), %xmm11
    sha256rnds2 %xmm0, 0x40(%r13), %xmm1
    sha256rnds2 %xmm0, (%rax,%r9,8), %xmm14
    sha256rnds2 %xmm0, 16(%r15,%rcx,2), %xmm3
    sha256rnds2 %xmm0, -4(%rdx,%r14,4), %xmm8
    sha1rnds4 $0xff, %xmm7, %xmm2
    sha1rnds4 $0, %xmm9, %xmm6
    sha1rnds4 $0x7f, %xmm3, %xmm8
    sha1rnds4 $0xff, %xmm15, %xmm11
    sha1rnds4 $0x7f, (%rax), %xmm3
    sha1rnds4 $0xff, 8(%rsp), %xmm8
    sha1rnds4 $0, -200(%rbp), %xmm7
    sha1rnds4 $0x7f, (%r12), %xmm11
    sha1rnds4 $0xff, 0x40(%r13), %xmm1
    sha1rnds4 $0, (%rax,%r9,8), %xmm14
    sha1rnds4 $0x7f, 16(%r15,%rcx,2), %xmm3
    sha1rnds4 $0xff, -4(%rdx,%r14,4), %xmm8
    vpaddb %xmm7, %xmm2, %xmm1
    vpaddb %xmm9, %xmm6, %xmm3
    vpaddb %xmm3, %xmm8, %xmm7
    vpaddb %xmm15, %xmm11, %xmm1
    vpaddb %xmm1, %xmm6, %xmm12
    vpaddb %xmm12, %xmm0, %xmm15
    vpaddb %xmm7, %xmm11, %xmm9
    vpaddb %xmm9, %xmm14, %xmm12
    vpaddb (%rax), %xmm14, %xmm3
    vpaddb 8(%rsp), %xmm3, %xmm8
    vpaddb -200(%rbp), %xmm8, %xmm7
    vpaddb (%r12), %xmm7, %xmm11
    vpaddb 0x40(%r13), %xmm11, %xmm1
    vpaddb (%rax,%r9,8), %xmm1, %xmm14
    vpaddb 16(%r15,%rcx,2), %xmm14, %xmm3
    vpaddb -4(%rdx,%r14,4), %xmm3, %xmm8
    vpaddb %ymm3, %ymm0, %ymm7
    vpaddb %ymm15, %ymm2, %ymm1
    vpaddb %ymm1, %ymm14, %ymm3
    vpaddb %ymm12, %ymm8, %ymm7
    vpaddb %ymm7, %ymm2, %ymm9
    vpaddb %ymm9, %ymm6, %ymm12
    vpaddb %ymm3, %ymm8, %ymm15
    vpaddb %ymm15, %ymm11, %ymm9
    vpaddb (%rax), %ymm14, %ymm3
    vpaddb 8(%rsp), %ymm3, %ymm8
    vpaddb -200(%rbp), %ymm8, %ymm7
    vpaddb (%r12), %ymm7, %ymm11
    vpaddb 0x40(%r13), %ymm11, %ymm1
    vpaddb (%rax,%r9,8), %ymm1, %ymm14
    vpaddb 16(%r15,%rcx,2), %ymm14, %ymm3
    vpaddb -4(%rdx,%r14,4), %ymm3, %ymm8
    vpaddw %xmm1, %xmm6, %xmm3
    vpaddw %xmm12, %xmm0, %xmm7
    vpaddw %xmm7, %xmm11, %xmm1
    vpaddw %xmm9, %xmm14, %xmm3
    vpaddw %xmm3, %xmm0, %xmm15
    vpaddw %xmm15, %xmm2, %xmm9
    vpaddw %xmm1, %xmm14, %xmm12
    vpaddw %xmm12, %xmm8, %xmm15
    vpaddw (%rax), %xmm14, %xmm3
    vpaddw 8(%rsp), %xmm3, %xmm8
    vpaddw -200(%rbp), %xmm8, %xmm7
    vpaddw (%r12), %xmm7, %xmm11
    vpaddw 0x40(%r13), %xmm11, %xmm1
    vpaddw (%rax,%r9,8), %xmm1, %xmm14
    vpaddw 16(%r15,%rcx,2), %xmm14, %xmm3
    vpaddw -4(%rdx,%r14,4), %xmm3, %xmm8
    vpaddw %ymm7, %ymm2, %ymm1
    vpaddw %ymm9, %ymm6, %ymm3
    vpaddw %ymm3, %ymm8, %ymm7
    vpaddw %ymm15, %ymm11, %ymm1
    vpaddw %ymm1, %ymm6, %ymm12
    vpaddw %ymm12, %ymm0, %ymm15
    vpaddw %ymm7, %ymm11, %ymm9
    vpaddw %ymm9, %ymm14, %ymm12
    vpaddw (%rax), %ymm14, %ymm3
    vpaddw 8(%rsp), %ymm3, %ymm8
    vpaddw -200(%rbp), %ymm8, %ymm7
    vpaddw (%r12), %ymm7, %ymm11
    vpaddw 0x40(%r13), %ymm11, %ymm1
    vpaddw (%rax,%r9,8), %ymm1, %ymm14
    vpaddw 16(%r15,%rcx,2), %ymm14, %ymm3
    vpaddw -4(%rdx,%r14,4), %ymm3, %ymm8
    vpaddd %xmm3, %xmm0, %xmm7
    vpaddd %xmm15, %xmm2, %xmm1
    vpaddd %xmm1, %xmm14, %xmm3
    vpaddd %xmm12, %xmm8, %xmm7
    vpaddd %xmm7, %xmm2, %xmm9
    vpaddd %xmm9, %xmm6, %xmm12
    vpaddd %xmm3, %xmm8, %xmm15
    vpaddd %xmm15, %xmm11, %xmm9
    vpaddd (%rax), %xmm14, %xmm3
    vpaddd 8(%rsp), %xmm3, %xmm8
    vpaddd -200(%rbp), %xmm8, %xmm7
    vpaddd (%r12), %xmm7, %xmm11
    vpaddd 0x40(%r13), %xmm11, %xmm1
    vpaddd (%rax,%r9,8), %xmm1, %xmm14
    vpaddd 16(%r15,%rcx,2), %xmm14, %xmm3
    vpaddd -4(%rdx,%r14,4), %xmm3, %xmm8
    vpaddd %ymm1, %ymm6, %ymm3
    vpaddd %ymm12, %ymm0, %ymm7
    vpaddd %ymm7, %ymm11, %ymm1
    vpaddd %ymm9, %ymm14, %ymm3
    vpaddd %ymm3, %ymm0, %ymm15
    vpaddd %ymm15, %ymm2, %ymm9
    vpaddd %ymm1, %ymm14, %ymm12
    vpaddd %ymm12, %ymm8, %ymm15
    vpaddd (%rax), %ymm14, %ymm3
    vpaddd 8(%rsp), %ymm3, %ymm8
    vpaddd -200(%rbp), %ymm8, %ymm7
    vpaddd (%r12), %ymm7, %ymm11
    vpaddd 0x40(%r13), %ymm11, %ymm1
    vpaddd (%rax,%r9,8), %ymm1, %ymm14
    vpaddd 16(%r15,%rcx,2), %ymm14, %ymm3
    vpaddd -4(%rdx,%r14,4), %ymm3, %ymm8
    vpaddq %xmm7, %xmm2, %xmm1
    vpaddq %xmm9, %xmm6, %xmm3
    vpaddq %xmm3, %xmm8, %xmm7
    vpaddq %xmm15, %xmm11, %xmm1
    vpaddq %xmm1, %xmm6, %xmm12
    vpaddq %xmm12, %xmm0, %xmm15
    vpaddq %xmm7, %xmm11, %xmm9
    vpaddq %xmm9, %xmm14, %xmm12
    vpaddq (%rax), %xmm14, %xmm3
    vpaddq 8(%rsp), %xmm3, %xmm8
    vpaddq -200(%rbp), %xmm8, %xmm7
    vpaddq (%r12), %xmm7, %xmm11
    vpaddq 0x40(%r13), %xmm11, %xmm1
    vpaddq (%rax,%r9,8), %xmm1, %xmm14
    vpaddq 16(%r15,%rcx,2), %xmm14, %xmm3
    vpaddq -4(%rdx,%r14,4), %xmm3, %xmm8
    vpaddq %ymm3, %ymm0, %ymm7
    vpaddq %ymm15, %ymm2, %ymm1
    vpaddq %ymm1, %ymm14, %ymm3
    vpaddq %ymm12, %ymm8, %ymm7
    vpaddq %ymm7, %ymm2, %ymm9
    vpaddq %ymm9, %ymm6, %ymm12
    vpaddq %ymm3, %ymm8, %ymm15
    vpaddq %ymm15, %ymm11, %ymm9
    vpaddq (%rax), %ymm14, %ymm3
    vpaddq 8(%rsp), %ymm3, %ymm8
    vpaddq -200(%rbp), %ymm8, %ymm7
    vpaddq (%r12), %ymm7, %ymm11
    vpaddq 0x40(%r13), %ymm11, %ymm1
    vpaddq (%rax,%r9,8), %ymm1, %ymm14
    vpaddq 16(%r15,%rcx,2), %ymm14, %ymm3
    vpaddq -4(%rdx,%r14,4), %ymm3, %ymm8
    vpaddsb %xmm1, %xmm6, %xmm3
    vpaddsb %xmm12, %xmm0, %xmm7
    vpaddsb %xmm7, %xmm11, %xmm1
    vpaddsb %xmm9, %xmm14, %xmm3
    vpaddsb %xmm3, %xmm0, %xmm15
    vpaddsb %xmm15, %xmm2, %xmm9
    vpaddsb %xmm1, %xmm14, %xmm12
    vpaddsb %xmm12, %xmm8, %xmm15
    vpaddsb (%rax), %xmm14, %xmm3
    vpaddsb 8(%rsp), %xmm3, %xmm8
    vpaddsb -200(%rbp), %xmm8, %xmm7
    vpaddsb (%r12), %xmm7, %xmm11
    vpaddsb 0x40(%r13), %xmm11, %xmm1
    vpaddsb (%rax,%r9,8), %xmm1, %xmm14
    vpaddsb 16(%r15,%rcx,2), %xmm14, %xmm3
    vpaddsb -4(%rdx,%r14,4), %xmm3, %xmm8
    vpaddsb %ymm7, %ymm2, %ymm1
    vpaddsb %ymm9, %ymm6, %ymm3
    vpaddsb %ymm3, %ymm8, %ymm7
    vpaddsb %ymm15, %ymm11, %ymm1
    vpaddsb %ymm1, %ymm6, %ymm12
    vpaddsb %ymm12, %ymm0, %ymm15
    vpaddsb %ymm7, %ymm11, %ymm9
    vpaddsb %ymm9, %ymm14, %ymm12
    vpaddsb (%rax), %ymm14, %ymm3
    vpaddsb 8(%rsp), %ymm3, %ymm8
    vpaddsb -200(%rbp), %ymm8, %ymm7
    vpaddsb (%r12), %ymm7, %ymm11
    vpaddsb 0x40(%r13), %ymm11, %ymm1
    vpaddsb (%rax,%r9,8), %ymm1, %ymm14
    vpaddsb 16(%r15,%rcx,2), %ymm14, %ymm3
    vpaddsb -4(%rdx,%r14,4), %ymm3, %ymm8
    vpaddsw %xmm3, %xmm0, %xmm7
    vpaddsw %xmm15, %xmm2, %xmm1
    vpaddsw %xmm1, %xmm14, %xmm3
    vpaddsw %xmm12, %xmm8, %xmm7
    vpaddsw %xmm7, %xmm2, %xmm9
    vpaddsw %xmm9, %xmm6, %xmm12
    vpaddsw %xmm3, %xmm8, %xmm15
    vpaddsw %xmm15, %xmm11, %xmm9
    vpaddsw (%rax), %xmm14, %xmm3
    vpaddsw 8(%rsp), %xmm3, %xmm8
    vpaddsw -200(%rbp), %xmm8, %xmm7
    vpaddsw (%r12), %xmm7, %xmm11
    vpaddsw 0x40(%r13), %xmm11, %xmm1
    vpaddsw (%rax,%r9,8), %xmm1, %xmm14
    vpaddsw 16(%r15,%rcx,2), %xmm14, %xmm3
    vpaddsw -4(%rdx,%r14,4), %xmm3, %xmm8
    vpaddsw %ymm1, %ymm6, %ymm3
    vpaddsw %ymm12, %ymm0, %ymm7
    vpaddsw %ymm7, %ymm11, %ymm1
    vpaddsw %ymm9, %ymm14, %ymm3
    vpaddsw %ymm3, %ymm0, %ymm15
    vpaddsw %ymm15, %ymm2, %ymm9
    vpaddsw %ymm1, %ymm14, %ymm12
    vpaddsw %ymm12, %ymm8, %ymm15
    vpaddsw (%rax), %ymm14, %ymm3
    vpaddsw 8(%rsp), %ymm3, %ymm8
    vpaddsw -200(%rbp), %ymm8, %ymm7
    vpaddsw (%r12), %ymm7, %ymm11
    vpaddsw 0x40(%r13), %ymm11, %ymm1
    vpaddsw (%rax,%r9,8), %ymm1, %ymm14
    vpaddsw 16(%r15,%rcx,2), %ymm14, %ymm3
    vpaddsw -4(%rdx,%r14,4), %ymm3, %ymm8
    vpaddusb %xmm7, %xmm2, %xmm1
    vpaddusb %xmm9, %xmm6, %xmm3
    vpaddusb %xmm3, %xmm8, %xmm7
    vpaddusb %xmm15, %xmm11, %xmm1
    vpaddusb %xmm1, %xmm6, %xmm12
    vpaddusb %xmm12, %xmm0, %xmm15
    vpaddusb %xmm7, %xmm11, %xmm9
    vpaddusb %xmm9, %xmm14, %xmm12
    vpaddusb (%rax), %xmm14, %xmm3
    vpaddusb 8(%rsp), %xmm3, %xmm8
    vpaddusb -200(%rbp), %xmm8, %xmm7
    vpaddusb (%r12), %xmm7, %xmm11
    vpaddusb 0x40(%r13), %xmm11, %xmm1
    vpaddusb (%rax,%r9,8), %xmm1, %xmm14
    vpaddusb 16(%r15,%rcx,2), %xmm14, %xmm3
    vpaddusb -4(%rdx,%r14,4), %xmm3, %xmm8
    vpaddusb %ymm3, %ymm0, %ymm7
    vpaddusb %ymm15, %ymm2, %ymm1
    vpaddusb %ymm1, %ymm14, %ymm3
    vpaddusb %ymm12, %ymm8, %ymm7
    vpaddusb %ymm7, %ymm2, %ymm9
    vpaddusb %ymm9, %ymm6, %ymm12
    vpaddusb %ymm3, %ymm8, %ymm15
    vpaddusb %ymm15, %ymm11, %ymm9
    vpaddusb (%rax), %ymm14, %ymm3
    vpaddusb 8(%rsp), %ymm3, %ymm8
    vpaddusb -200(%rbp), %ymm8, %ymm7
    vpaddusb (%r12), %ymm7, %ymm11
    vpaddusb 0x40(%r13), %ymm11, %ymm1
    vpaddusb (%rax,%r9,8), %ymm1, %ymm14
    vpaddusb 16(%r15,%rcx,2), %ymm14, %ymm3
    vpaddusb -4(%rdx,%r14,4), %ymm3, %ymm8
    vpaddusw %xmm1, %xmm6, %xmm3
    vpaddusw %xmm12, %xmm0, %xmm7
    vpaddusw %xmm7, %xmm11, %xmm1
    vpaddusw %xmm9, %xmm14, %xmm3
    vpaddusw %xmm3, %xmm0, %xmm15
    vpaddusw %xmm15, %xmm2, %xmm9
    vpaddusw %xmm1, %xmm14, %xmm12
    vpaddusw %xmm12, %xmm8, %xmm15
    vpaddusw (%rax), %xmm14, %xmm3
    vpaddusw 8(%rsp), %xmm3, %xmm8
    vpaddusw -200(%rbp), %xmm8, %xmm7
    vpaddusw (%r12), %xmm7, %xmm11
    vpaddusw 0x40(%r13), %xmm11, %xmm1
    vpaddusw (%rax,%r9,8), %xmm1, %xmm14
    vpaddusw 16(%r15,%rcx,2), %xmm14, %xmm3
    vpaddusw -4(%rdx,%r14,4), %xmm3, %xmm8
    vpaddusw %ymm7, %ymm2, %ymm1
    vpaddusw %ymm9, %ymm6, %ymm3
    vpaddusw %ymm3, %ymm8, %ymm7
    vpaddusw %ymm15, %ymm11, %ymm1
    vpaddusw %ymm1, %ymm6, %ymm12
    vpaddusw %ymm12, %ymm0, %ymm15
    vpaddusw %ymm7, %ymm11, %ymm9
    vpaddusw %ymm9, %ymm14, %ymm12
    vpaddusw (%rax), %ymm14, %ymm3
    vpaddusw 8(%rsp), %ymm3, %ymm8
    vpaddusw -200(%rbp), %ymm8, %ymm7
    vpaddusw (%r12), %ymm7, %ymm11
    vpaddusw 0x40(%r13), %ymm11, %ymm1
    vpaddusw (%rax,%r9,8), %ymm1, %ymm14
    vpaddusw 16(%r15,%rcx,2), %ymm14, %ymm3
    vpaddusw -4(%rdx,%r14,4), %ymm3, %ymm8
    vpmullw %xmm3, %xmm0, %xmm7
    vpmullw %xmm15, %xmm2, %xmm1
    vpmullw %xmm1, %xmm14, %xmm3
    vpmullw %xmm12, %xmm8, %xmm7
    vpmullw %xmm7, %xmm2, %xmm9
    vpmullw %xmm9, %xmm6, %xmm12
    vpmullw %xmm3, %xmm8, %xmm15
    vpmullw %xmm15, %xmm11, %xmm9
    vpmullw (%rax), %xmm14, %xmm3
    vpmullw 8(%rsp), %xmm3, %xmm8
    vpmullw -200(%rbp), %xmm8, %xmm7
    vpmullw (%r12), %xmm7, %xmm11
    vpmullw 0x40(%r13), %xmm11, %xmm1
    vpmullw (%rax,%r9,8), %xmm1, %xmm14
    vpmullw 16(%r15,%rcx,2), %xmm14, %xmm3
    vpmullw -4(%rdx,%r14,4), %xmm3, %xmm8
    vpmullw %ymm1, %ymm6, %ymm3
    vpmullw %ymm12, %ymm0, %ymm7
    vpmullw %ymm7, %ymm11, %ymm1
    vpmullw %ymm9, %ymm14, %ymm3
    vpmullw %ymm3, %ymm0, %ymm15
    vpmullw %ymm15, %ymm2, %ymm9
    vpmullw %ymm1, %ymm14, %ymm12
    vpmullw %ymm12, %ymm8, %ymm15
    vpmullw (%rax), %ymm14, %ymm3
    vpmullw 8(%rsp), %ymm3, %ymm8
    vpmullw -200(%rbp), %ymm8, %ymm7
    vpmullw (%r12), %ymm7, %ymm11
    vpmullw 0x40(%r13), %ymm11, %ymm1
    vpmullw (%rax,%r9,8), %ymm1, %ymm14
    vpmullw 16(%r15,%rcx,2), %ymm14, %ymm3
    vpmullw -4(%rdx,%r14,4), %ymm3, %ymm8
    vpmulhw %xmm7, %xmm2, %xmm1
    vpmulhw %xmm9, %xmm6, %xmm3
    vpmulhw %xmm3, %xmm8, %xmm7
    vpmulhw %xmm15, %xmm11, %xmm1
    vpmulhw %xmm1, %xmm6, %xmm12
    vpmulhw %xmm12, %xmm0, %xmm15
    vpmulhw %xmm7, %xmm11, %xmm9
    vpmulhw %xmm9, %xmm14, %xmm12
    vpmulhw (%rax), %xmm14, %xmm3
    vpmulhw 8(%rsp), %xmm3, %xmm8
    vpmulhw -200(%rbp), %xmm8, %xmm7
    vpmulhw (%r12), %xmm7, %xmm11
    vpmulhw 0x40(%r13), %xmm11, %xmm1
    vpmulhw (%rax,%r9,8), %xmm1, %xmm14
    vpmulhw 16(%r15,%rcx,2), %xmm14, %xmm3
    vpmulhw -4(%rdx,%r14,4), %xmm3, %xmm8
    vpmulhw %ymm3, %ymm0, %ymm7
    vpmulhw %ymm15, %ymm2, %ymm1
    vpmulhw %ymm1, %ymm14, %ymm3
    vpmulhw %ymm12, %ymm8, %ymm7
    vpmulhw %ymm7, %ymm2, %ymm9
    vpmulhw %ymm9, %ymm6, %ymm12
    vpmulhw %ymm3, %ymm8, %ymm15
    vpmulhw %ymm15, %ymm11, %ymm9
    vpmulhw (%rax), %ymm14, %ymm3
    vpmulhw 8(%rsp), %ymm3, %ymm8
    vpmulhw -200(%rbp), %ymm8, %ymm7
    vpmulhw (%r12), %ymm7, %ymm11
    vpmulhw 0x40(%r13), %ymm11, %ymm1
    vpmulhw (%rax,%r9,8), %ymm1, %ymm14
    vpmulhw 16(%r15,%rcx,2), %ymm14, %ymm3
    vpmulhw -4(%rdx,%r14,4), %ymm3, %ymm8
    vpmulhuw %xmm1, %xmm6, %xmm3
    vpmulhuw %xmm12, %xmm0, %xmm7
    vpmulhuw %xmm7, %xmm11, %xmm1
    vpmulhuw %xmm9, %xmm14, %xmm3
    vpmulhuw %xmm3, %xmm0, %xmm15
    vpmulhuw %xmm15, %xmm2, %xmm9
    vpmulhuw %xmm1, %xmm14, %xmm12
    vpmulhuw %xmm12, %xmm8, %xmm15
    vpmulhuw (%rax), %xmm14, %xmm3
    vpmulhuw 8(%rsp), %xmm3, %xmm8
    vpmulhuw -200(%rbp), %xmm8, %xmm7
    vpmulhuw (%r12), %xmm7, %xmm11
    vpmulhuw 0x40(%r13), %xmm11, %xmm1
    vpmulhuw (%rax,%r9,8), %xmm1, %xmm14
    vpmulhuw 16(%r15,%rcx,2), %xmm14, %xmm3
    vpmulhuw -4(%rdx,%r14,4), %xmm3, %xmm8
    vpmulhuw %ymm7, %ymm2, %ymm1
    vpmulhuw %ymm9, %ymm6, %ymm3
    vpmulhuw %ymm3, %ymm8, %ymm7
    vpmulhuw %ymm15, %ymm11, %ymm1
    vpmulhuw %ymm1, %ymm6, %ymm12
    vpmulhuw %ymm12, %ymm0, %ymm15
    vpmulhuw %ymm7, %ymm11, %ymm9
    vpmulhuw %ymm9, %ymm14, %ymm12
    vpmulhuw (%rax), %ymm14, %ymm3
    vpmulhuw 8(%rsp), %ymm3, %ymm8
    vpmulhuw -200(%rbp), %ymm8, %ymm7
    vpmulhuw (%r12), %ymm7, %ymm11
    vpmulhuw 0x40(%r13), %ymm11, %ymm1
    vpmulhuw (%rax,%r9,8), %ymm1, %ymm14
    vpmulhuw 16(%r15,%rcx,2), %ymm14, %ymm3
    vpmulhuw -4(%rdx,%r14,4), %ymm3, %ymm8
    vpmuludq %xmm3, %xmm0, %xmm7
    vpmuludq %xmm15, %xmm2, %xmm1
    vpmuludq %xmm1, %xmm14, %xmm3
    vpmuludq %xmm12, %xmm8, %xmm7
    vpmuludq %xmm7, %xmm2, %xmm9
    vpmuludq %xmm9, %xmm6, %xmm12
    vpmuludq %xmm3, %xmm8, %xmm15
    vpmuludq %xmm15, %xmm11, %xmm9
    vpmuludq (%rax), %xmm14, %xmm3
    vpmuludq 8(%rsp), %xmm3, %xmm8
    vpmuludq -200(%rbp), %xmm8, %xmm7
    vpmuludq (%r12), %xmm7, %xmm11
    vpmuludq 0x40(%r13), %xmm11, %xmm1
    vpmuludq (%rax,%r9,8), %xmm1, %xmm14
    vpmuludq 16(%r15,%rcx,2), %xmm14, %xmm3
    vpmuludq -4(%rdx,%r14,4), %xmm3, %xmm8
    vpmuludq %ymm1, %ymm6, %ymm3
    vpmuludq %ymm12, %ymm0, %ymm7
    vpmuludq %ymm7, %ymm11, %ymm1
    vpmuludq %ymm9, %ymm14, %ymm3
    vpmuludq %ymm3, %ymm0, %ymm15
    vpmuludq %ymm15, %ymm2, %ymm9
    vpmuludq %ymm1, %ymm14, %ymm12
    vpmuludq %ymm12, %ymm8, %ymm15
    vpmuludq (%rax), %ymm14, %ymm3
    vpmuludq 8(%rsp), %ymm3, %ymm8
    vpmuludq -200(%rbp), %ymm8, %ymm7
    vpmuludq (%r12), %ymm7, %ymm11
    vpmuludq 0x40(%r13), %ymm11, %ymm1
    vpmuludq (%rax,%r9,8), %ymm1, %ymm14
    vpmuludq 16(%r15,%rcx,2), %ymm14, %ymm3
    vpmuludq -4(%rdx,%r14,4), %ymm3, %ymm8
    vpmaddwd %xmm7, %xmm2, %xmm1
    vpmaddwd %xmm9, %xmm6, %xmm3
    vpmaddwd %xmm3, %xmm8, %xmm7
    vpmaddwd %xmm15, %xmm11, %xmm1
    vpmaddwd %xmm1, %xmm6, %xmm12
    vpmaddwd %xmm12, %xmm0, %xmm15
    vpmaddwd %xmm7, %xmm11, %xmm9
    vpmaddwd %xmm9, %xmm14, %xmm12
    vpmaddwd (%rax), %xmm14, %xmm3
    vpmaddwd 8(%rsp), %xmm3, %xmm8
    vpmaddwd -200(%rbp), %xmm8, %xmm7
    vpmaddwd (%r12), %xmm7, %xmm11
    vpmaddwd 0x40(%r13), %xmm11, %xmm1
    vpmaddwd (%rax,%r9,8), %xmm1, %xmm14
    vpmaddwd 16(%r15,%rcx,2), %xmm14, %xmm3
    vpmaddwd -4(%rdx,%r14,4), %xmm3, %xmm8
    vpmaddwd %ymm3, %ymm0, %ymm7
    vpmaddwd %ymm15, %ymm2, %ymm1
    vpmaddwd %ymm1, %ymm14, %ymm3
    vpmaddwd %ymm12, %ymm8, %ymm7
    vpmaddwd %ymm7, %ymm2, %ymm9
    vpmaddwd %ymm9, %ymm6, %ymm12
    vpmaddwd %ymm3, %ymm8, %ymm15
    vpmaddwd %ymm15, %ymm11, %ymm9
    vpmaddwd (%rax), %ymm14, %ymm3
    vpmaddwd 8(%rsp), %ymm3, %ymm8
    vpmaddwd -200(%rbp), %ymm8, %ymm7
    vpmaddwd (%r12), %ymm7, %ymm11
    vpmaddwd 0x40(%r13), %ymm11, %ymm1
    vpmaddwd (%rax,%r9,8), %ymm1, %ymm14
    vpmaddwd 16(%r15,%rcx,2), %ymm14, %ymm3
    vpmaddwd -4(%rdx,%r14,4), %ymm3, %ymm8
    vpsadbw %xmm1, %xmm6, %xmm3
    vpsadbw %xmm12, %xmm0, %xmm7
    vpsadbw %xmm7, %xmm11, %xmm1
    vpsadbw %xmm9, %xmm14, %xmm3
    vpsadbw %xmm3, %xmm0, %xmm15
    vpsadbw %xmm15, %xmm2, %xmm9
    vpsadbw %xmm1, %xmm14, %xmm12
    vpsadbw %xmm12, %xmm8, %xmm15
    vpsadbw (%rax), %xmm14, %xmm3
    vpsadbw 8(%rsp), %xmm3, %xmm8
    vpsadbw -200(%rbp), %xmm8, %xmm7
    vpsadbw (%r12), %xmm7, %xmm11
    vpsadbw 0x40(%r13), %xmm11, %xmm1
    vpsadbw (%rax,%r9,8), %xmm1, %xmm14
    vpsadbw 16(%r15,%rcx,2), %xmm14, %xmm3
    vpsadbw -4(%rdx,%r14,4), %xmm3, %xmm8
    vpsadbw %ymm7, %ymm2, %ymm1
    vpsadbw %ymm9, %ymm6, %ymm3
    vpsadbw %ymm3, %ymm8, %ymm7
    vpsadbw %ymm15, %ymm11, %ymm1
    vpsadbw %ymm1, %ymm6, %ymm12
    vpsadbw %ymm12, %ymm0, %ymm15
    vpsadbw %ymm7, %ymm11, %ymm9
    vpsadbw %ymm9, %ymm14, %ymm12
    vpsadbw (%rax), %ymm14, %ymm3
    vpsadbw 8(%rsp), %ymm3, %ymm8
    vpsadbw -200(%rbp), %ymm8, %ymm7
    vpsadbw (%r12), %ymm7, %ymm11
    vpsadbw 0x40(%r13), %ymm11, %ymm1
    vpsadbw (%rax,%r9,8), %ymm1, %ymm14
    vpsadbw 16(%r15,%rcx,2), %ymm14, %ymm3
    vpsadbw -4(%rdx,%r14,4), %ymm3, %ymm8
    vpavgb %xmm3, %xmm0, %xmm7
    vpavgb %xmm15, %xmm2, %xmm1
    vpavgb %xmm1, %xmm14, %xmm3
    vpavgb %xmm12, %xmm8, %xmm7
    vpavgb %xmm7, %xmm2, %xmm9
    vpavgb %xmm9, %xmm6, %xmm12
    vpavgb %xmm3, %xmm8, %xmm15
    vpavgb %xmm15, %xmm11, %xmm9
    vpavgb (%rax), %xmm14, %xmm3
    vpavgb 8(%rsp), %xmm3, %xmm8
    vpavgb -200(%rbp), %xmm8, %xmm7
    vpavgb (%r12), %xmm7, %xmm11
    vpavgb 0x40(%r13), %xmm11, %xmm1
    vpavgb (%rax,%r9,8), %xmm1, %xmm14
    vpavgb 16(%r15,%rcx,2), %xmm14, %xmm3
    vpavgb -4(%rdx,%r14,4), %xmm3, %xmm8
    vpavgb %ymm1, %ymm6, %ymm3
    vpavgb %ymm12, %ymm0, %ymm7
    vpavgb %ymm7, %ymm11, %ymm1
    vpavgb %ymm9, %ymm14, %ymm3
    vpavgb %ymm3, %ymm0, %ymm15
    vpavgb %ymm15, %ymm2, %ymm9
    vpavgb %ymm1, %ymm14, %ymm12
    vpavgb %ymm12, %ymm8, %ymm15
    vpavgb (%rax), %ymm14, %ymm3
    vpavgb 8(%rsp), %ymm3, %ymm8
    vpavgb -200(%rbp), %ymm8, %ymm7
    vpavgb (%r12), %ymm7, %ymm11
    vpavgb 0x40(%r13), %ymm11, %ymm1
    vpavgb (%rax,%r9,8), %ymm1, %ymm14
    vpavgb 16(%r15,%rcx,2), %ymm14, %ymm3
    vpavgb -4(%rdx,%r14,4), %ymm3, %ymm8
    vpavgw %xmm7, %xmm2, %xmm1
    vpavgw %xmm9, %xmm6, %xmm3
    vpavgw %xmm3, %xmm8, %xmm7
    vpavgw %xmm15, %xmm11, %xmm1
    vpavgw %xmm1, %xmm6, %xmm12
    vpavgw %xmm12, %xmm0, %xmm15
    vpavgw %xmm7, %xmm11, %xmm9
    vpavgw %xmm9, %xmm14, %xmm12
    vpavgw (%rax), %xmm14, %xmm3
    vpavgw 8(%rsp), %xmm3, %xmm8
    vpavgw -200(%rbp), %xmm8, %xmm7
    vpavgw (%r12), %xmm7, %xmm11
    vpavgw 0x40(%r13), %xmm11, %xmm1
    vpavgw (%rax,%r9,8), %xmm1, %xmm14
    vpavgw 16(%r15,%rcx,2), %xmm14, %xmm3
    vpavgw -4(%rdx,%r14,4), %xmm3, %xmm8
    vpavgw %ymm3, %ymm0, %ymm7
    vpavgw %ymm15, %ymm2, %ymm1
    vpavgw %ymm1, %ymm14, %ymm3
    vpavgw %ymm12, %ymm8, %ymm7
    vpavgw %ymm7, %ymm2, %ymm9
    vpavgw %ymm9, %ymm6, %ymm12
    vpavgw %ymm3, %ymm8, %ymm15
    vpavgw %ymm15, %ymm11, %ymm9
    vpavgw (%rax), %ymm14, %ymm3
    vpavgw 8(%rsp), %ymm3, %ymm8
    vpavgw -200(%rbp), %ymm8, %ymm7
    vpavgw (%r12), %ymm7, %ymm11
    vpavgw 0x40(%r13), %ymm11, %ymm1
    vpavgw (%rax,%r9,8), %ymm1, %ymm14
    vpavgw 16(%r15,%rcx,2), %ymm14, %ymm3
    vpavgw -4(%rdx,%r14,4), %ymm3, %ymm8
    vpminub %xmm1, %xmm6, %xmm3
    vpminub %xmm12, %xmm0, %xmm7
    vpminub %xmm7, %xmm11, %xmm1
    vpminub %xmm9, %xmm14, %xmm3
    vpminub %xmm3, %xmm0, %xmm15
    vpminub %xmm15, %xmm2, %xmm9
    vpminub %xmm1, %xmm14, %xmm12
    vpminub %xmm12, %xmm8, %xmm15
    vpminub (%rax), %xmm14, %xmm3
    vpminub 8(%rsp), %xmm3, %xmm8
    vpminub -200(%rbp), %xmm8, %xmm7
    vpminub (%r12), %xmm7, %xmm11
    vpminub 0x40(%r13), %xmm11, %xmm1
    vpminub (%rax,%r9,8), %xmm1, %xmm14
    vpminub 16(%r15,%rcx,2), %xmm14, %xmm3
    vpminub -4(%rdx,%r14,4), %xmm3, %xmm8
    vpminub %ymm7, %ymm2, %ymm1
    vpminub %ymm9, %ymm6, %ymm3
    vpminub %ymm3, %ymm8, %ymm7
    vpminub %ymm15, %ymm11, %ymm1
    vpminub %ymm1, %ymm6, %ymm12
    vpminub %ymm12, %ymm0, %ymm15
    vpminub %ymm7, %ymm11, %ymm9
    vpminub %ymm9, %ymm14, %ymm12
    vpminub (%rax), %ymm14, %ymm3
    vpminub 8(%rsp), %ymm3, %ymm8
    vpminub -200(%rbp), %ymm8, %ymm7
    vpminub (%r12), %ymm7, %ymm11
    vpminub 0x40(%r13), %ymm11, %ymm1
    vpminub (%rax,%r9,8), %ymm1, %ymm14
    vpminub 16(%r15,%rcx,2), %ymm14, %ymm3
    vpminub -4(%rdx,%r14,4), %ymm3, %ymm8
    vpmaxub %xmm3, %xmm0, %xmm7
    vpmaxub %xmm15, %xmm2, %xmm1
    vpmaxub %xmm1, %xmm14, %xmm3
    vpmaxub %xmm12, %xmm8, %xmm7
    vpmaxub %xmm7, %xmm2, %xmm9
    vpmaxub %xmm9, %xmm6, %xmm12
    vpmaxub %xmm3, %xmm8, %xmm15
    vpmaxub %xmm15, %xmm11, %xmm9
    vpmaxub (%rax), %xmm14, %xmm3
    vpmaxub 8(%rsp), %xmm3, %xmm8
    vpmaxub -200(%rbp), %xmm8, %xmm7
    vpmaxub (%r12), %xmm7, %xmm11
    vpmaxub 0x40(%r13), %xmm11, %xmm1
    vpmaxub (%rax,%r9,8), %xmm1, %xmm14
    vpmaxub 16(%r15,%rcx,2), %xmm14, %xmm3
    vpmaxub -4(%rdx,%r14,4), %xmm3, %xmm8
    vpmaxub %ymm1, %ymm6, %ymm3
    vpmaxub %ymm12, %ymm0, %ymm7
    vpmaxub %ymm7, %ymm11, %ymm1
    vpmaxub %ymm9, %ymm14, %ymm3
    vpmaxub %ymm3, %ymm0, %ymm15
    vpmaxub %ymm15, %ymm2, %ymm9
    vpmaxub %ymm1, %ymm14, %ymm12
    vpmaxub %ymm12, %ymm8, %ymm15
    vpmaxub (%rax), %ymm14, %ymm3
    vpmaxub 8(%rsp), %ymm3, %ymm8
    vpmaxub -200(%rbp), %ymm8, %ymm7
    vpmaxub (%r12), %ymm7, %ymm11
    vpmaxub 0x40(%r13), %ymm11, %ymm1
    vpmaxub (%rax,%r9,8), %ymm1, %ymm14
    vpmaxub 16(%r15,%rcx,2), %ymm14, %ymm3
    vpmaxub -4(%rdx,%r14,4), %ymm3, %ymm8
    vpminsw %xmm7, %xmm2, %xmm1
    vpminsw %xmm9, %xmm6, %xmm3
    vpminsw %xmm3, %xmm8, %xmm7
    vpminsw %xmm15, %xmm11, %xmm1
    vpminsw %xmm1, %xmm6, %xmm12
    vpminsw %xmm12, %xmm0, %xmm15
    vpminsw %xmm7, %xmm11, %xmm9
    vpminsw %xmm9, %xmm14, %xmm12
    vpminsw (%rax), %xmm14, %xmm3
    vpminsw 8(%rsp), %xmm3, %xmm8
    vpminsw -200(%rbp), %xmm8, %xmm7
    vpminsw (%r12), %xmm7, %xmm11
    vpminsw 0x40(%r13), %xmm11, %xmm1
    vpminsw (%rax,%r9,8), %xmm1, %xmm14
    vpminsw 16(%r15,%rcx,2), %xmm14, %xmm3
    vpminsw -4(%rdx,%r14,4), %xmm3, %xmm8
    vpminsw %ymm3, %ymm0, %ymm7
    vpminsw %ymm15, %ymm2, %ymm1
    vpminsw %ymm1, %ymm14, %ymm3
    vpminsw %ymm12, %ymm8, %ymm7
    vpminsw %ymm7, %ymm2, %ymm9
    vpminsw %ymm9, %ymm6, %ymm12
    vpminsw %ymm3, %ymm8, %ymm15
    vpminsw %ymm15, %ymm11, %ymm9
    vpminsw (%rax), %ymm14, %ymm3
    vpminsw 8(%rsp), %ymm3, %ymm8
    vpminsw -200(%rbp), %ymm8, %ymm7
    vpminsw (%r12), %ymm7, %ymm11
    vpminsw 0x40(%r13), %ymm11, %ymm1
    vpminsw (%rax,%r9,8), %ymm1, %ymm14
    vpminsw 16(%r15,%rcx,2), %ymm14, %ymm3
    vpminsw -4(%rdx,%r14,4), %ymm3, %ymm8
    vpmaxsw %xmm1, %xmm6, %xmm3
    vpmaxsw %xmm12, %xmm0, %xmm7
    vpmaxsw %xmm7, %xmm11, %xmm1
    vpmaxsw %xmm9, %xmm14, %xmm3
    vpmaxsw %xmm3, %xmm0, %xmm15
    vpmaxsw %xmm15, %xmm2, %xmm9
    vpmaxsw %xmm1, %xmm14, %xmm12
    vpmaxsw %xmm12, %xmm8, %xmm15
    vpmaxsw (%rax), %xmm14, %xmm3
    vpmaxsw 8(%rsp), %xmm3, %xmm8
    vpmaxsw -200(%rbp), %xmm8, %xmm7
    vpmaxsw (%r12), %xmm7, %xmm11
    vpmaxsw 0x40(%r13), %xmm11, %xmm1
    vpmaxsw (%rax,%r9,8), %xmm1, %xmm14
    vpmaxsw 16(%r15,%rcx,2), %xmm14, %xmm3
    vpmaxsw -4(%rdx,%r14,4), %xmm3, %xmm8
    vpmaxsw %ymm7, %ymm2, %ymm1
    vpmaxsw %ymm9, %ymm6, %ymm3
    vpmaxsw %ymm3, %ymm8, %ymm7
    vpmaxsw %ymm15, %ymm11, %ymm1
    vpmaxsw %ymm1, %ymm6, %ymm12
    vpmaxsw %ymm12, %ymm0, %ymm15
    vpmaxsw %ymm7, %ymm11, %ymm9
    vpmaxsw %ymm9, %ymm14, %ymm12
    vpmaxsw (%rax), %ymm14, %ymm3
    vpmaxsw 8(%rsp), %ymm3, %ymm8
    vpmaxsw -200(%rbp), %ymm8, %ymm7
    vpmaxsw (%r12), %ymm7, %ymm11
    vpmaxsw 0x40(%r13), %ymm11, %ymm1
    vpmaxsw (%rax,%r9,8), %ymm1, %ymm14
    vpmaxsw 16(%r15,%rcx,2), %ymm14, %ymm3
    vpmaxsw -4(%rdx,%r14,4), %ymm3, %ymm8
    vpcmpeqb %xmm3, %xmm0, %xmm7
    vpcmpeqb %xmm15, %xmm2, %xmm1
    vpcmpeqb %xmm1, %xmm14, %xmm3
    vpcmpeqb %xmm12, %xmm8, %xmm7
    vpcmpeqb %xmm7, %xmm2, %xmm9
    vpcmpeqb %xmm9, %xmm6, %xmm12
    vpcmpeqb %xmm3, %xmm8, %xmm15
    vpcmpeqb %xmm15, %xmm11, %xmm9
    vpcmpeqb (%rax), %xmm14, %xmm3
    vpcmpeqb 8(%rsp), %xmm3, %xmm8
    vpcmpeqb -200(%rbp), %xmm8, %xmm7
    vpcmpeqb (%r12), %xmm7, %xmm11
    vpcmpeqb 0x40(%r13), %xmm11, %xmm1
    vpcmpeqb (%rax,%r9,8), %xmm1, %xmm14
    vpcmpeqb 16(%r15,%rcx,2), %xmm14, %xmm3
    vpcmpeqb -4(%rdx,%r14,4), %xmm3, %xmm8
    vpcmpeqb %ymm1, %ymm6, %ymm3
    vpcmpeqb %ymm12, %ymm0, %ymm7
    vpcmpeqb %ymm7, %ymm11, %ymm1
    vpcmpeqb %ymm9, %ymm14, %ymm3
    vpcmpeqb %ymm3, %ymm0, %ymm15
    vpcmpeqb %ymm15, %ymm2, %ymm9
    vpcmpeqb %ymm1, %ymm14, %ymm12
    vpcmpeqb %ymm12, %ymm8, %ymm15
    vpcmpeqb (%rax), %ymm14, %ymm3
    vpcmpeqb 8(%rsp), %ymm3, %ymm8
    vpcmpeqb -200(%rbp), %ymm8, %ymm7
    vpcmpeqb (%r12), %ymm7, %ymm11
    vpcmpeqb 0x40(%r13), %ymm11, %ymm1
    vpcmpeqb (%rax,%r9,8), %ymm1, %ymm14
    vpcmpeqb 16(%r15,%rcx,2), %ymm14, %ymm3
    vpcmpeqb -4(%rdx,%r14,4), %ymm3, %ymm8
    vpcmpeqw %xmm7, %xmm2, %xmm1
    vpcmpeqw %xmm9, %xmm6, %xmm3
    vpcmpeqw %xmm3, %xmm8, %xmm7
    vpcmpeqw %xmm15, %xmm11, %xmm1
    vpcmpeqw %xmm1, %xmm6, %xmm12
    vpcmpeqw %xmm12, %xmm0, %xmm15
    vpcmpeqw %xmm7, %xmm11, %xmm9
    vpcmpeqw %xmm9, %xmm14, %xmm12
    vpcmpeqw (%rax), %xmm14, %xmm3
    vpcmpeqw 8(%rsp), %xmm3, %xmm8
    vpcmpeqw -200(%rbp), %xmm8, %xmm7
    vpcmpeqw (%r12), %xmm7, %xmm11
    vpcmpeqw 0x40(%r13), %xmm11, %xmm1
    vpcmpeqw (%rax,%r9,8), %xmm1, %xmm14
    vpcmpeqw 16(%r15,%rcx,2), %xmm14, %xmm3
    vpcmpeqw -4(%rdx,%r14,4), %xmm3, %xmm8
    vpcmpeqw %ymm3, %ymm0, %ymm7
    vpcmpeqw %ymm15, %ymm2, %ymm1
    vpcmpeqw %ymm1, %ymm14, %ymm3
    vpcmpeqw %ymm12, %ymm8, %ymm7
    vpcmpeqw %ymm7, %ymm2, %ymm9
    vpcmpeqw %ymm9, %ymm6, %ymm12
    vpcmpeqw %ymm3, %ymm8, %ymm15
    vpcmpeqw %ymm15, %ymm11, %ymm9
    vpcmpeqw (%rax), %ymm14, %ymm3
    vpcmpeqw 8(%rsp), %ymm3, %ymm8
    vpcmpeqw -200(%rbp), %ymm8, %ymm7
    vpcmpeqw (%r12), %ymm7, %ymm11
    vpcmpeqw 0x40(%r13), %ymm11, %ymm1
    vpcmpeqw (%rax,%r9,8), %ymm1, %ymm14
    vpcmpeqw 16(%r15,%rcx,2), %ymm14, %ymm3
    vpcmpeqw -4(%rdx,%r14,4), %ymm3, %ymm8
    vpcmpeqd %xmm1, %xmm6, %xmm3
    vpcmpeqd %xmm12, %xmm0, %xmm7
    vpcmpeqd %xmm7, %xmm11, %xmm1
    vpcmpeqd %xmm9, %xmm14, %xmm3
    vpcmpeqd %xmm3, %xmm0, %xmm15
    vpcmpeqd %xmm15, %xmm2, %xmm9
    vpcmpeqd %xmm1, %xmm14, %xmm12
    vpcmpeqd %xmm12, %xmm8, %xmm15
    vpcmpeqd (%rax), %xmm14, %xmm3
    vpcmpeqd 8(%rsp), %xmm3, %xmm8
    vpcmpeqd -200(%rbp), %xmm8, %xmm7
    vpcmpeqd (%r12), %xmm7, %xmm11
    vpcmpeqd 0x40(%r13), %xmm11, %xmm1
    vpcmpeqd (%rax,%r9,8), %xmm1, %xmm14
    vpcmpeqd 16(%r15,%rcx,2), %xmm14, %xmm3
    vpcmpeqd -4(%rdx,%r14,4), %xmm3, %xmm8
    vpcmpeqd %ymm7, %ymm2, %ymm1
    vpcmpeqd %ymm9, %ymm6, %ymm3
    vpcmpeqd %ymm3, %ymm8, %ymm7
    vpcmpeqd %ymm15, %ymm11, %ymm1
    vpcmpeqd %ymm1, %ymm6, %ymm12
    vpcmpeqd %ymm12, %ymm0, %ymm15
    vpcmpeqd %ymm7, %ymm11, %ymm9
    vpcmpeqd %ymm9, %ymm14, %ymm12
    vpcmpeqd (%rax), %ymm14, %ymm3
    vpcmpeqd 8(%rsp), %ymm3, %ymm8
    vpcmpeqd -200(%rbp), %ymm8, %ymm7
    vpcmpeqd (%r12), %ymm7, %ymm11
    vpcmpeqd 0x40(%r13), %ymm11, %ymm1
    vpcmpeqd (%rax,%r9,8), %ymm1, %ymm14
    vpcmpeqd 16(%r15,%rcx,2), %ymm14, %ymm3
    vpcmpeqd -4(%rdx,%r14,4), %ymm3, %ymm8
    vpand %xmm3, %xmm0, %xmm7
    vpand %xmm15, %xmm2, %xmm1
    vpand %xmm1, %xmm14, %xmm3
    vpand %xmm12, %xmm8, %xmm7
    vpand %xmm7, %xmm2, %xmm9
    vpand %xmm9, %xmm6, %xmm12
    vpand %xmm3, %xmm8, %xmm15
    vpand %xmm15, %xmm11, %xmm9
    vpand (%rax), %xmm14, %xmm3
    vpand 8(%rsp), %xmm3, %xmm8
    vpand -200(%rbp), %xmm8, %xmm7
    vpand (%r12), %xmm7, %xmm11
    vpand 0x40(%r13), %xmm11, %xmm1
    vpand (%rax,%r9,8), %xmm1, %xmm14
    vpand 16(%r15,%rcx,2), %xmm14, %xmm3
    vpand -4(%rdx,%r14,4), %xmm3, %xmm8
    vpand %ymm1, %ymm6, %ymm3
    vpand %ymm12, %ymm0, %ymm7
    vpand %ymm7, %ymm11, %ymm1
    vpand %ymm9, %ymm14, %ymm3
    vpand %ymm3, %ymm0, %ymm15
    vpand %ymm15, %ymm2, %ymm9
    vpand %ymm1, %ymm14, %ymm12
    vpand %ymm12, %ymm8, %ymm15
    vpand (%rax), %ymm14, %ymm3
    vpand 8(%rsp), %ymm3, %ymm8
    vpand -200(%rbp), %ymm8, %ymm7
    vpand (%r12), %ymm7, %ymm11
    vpand 0x40(%r13), %ymm11, %ymm1
    vpand (%rax,%r9,8), %ymm1, %ymm14
    vpand 16(%r15,%rcx,2), %ymm14, %ymm3
    vpand -4(%rdx,%r14,4), %ymm3, %ymm8
    vpor %xmm7, %xmm2, %xmm1
    vpor %xmm9, %xmm6, %xmm3
    vpor %xmm3, %xmm8, %xmm7
    vpor %xmm15, %xmm11, %xmm1
    vpor %xmm1, %xmm6, %xmm12
    vpor %xmm12, %xmm0, %xmm15
    vpor %xmm7, %xmm11, %xmm9
    vpor %xmm9, %xmm14, %xmm12
    vpor (%rax), %xmm14, %xmm3
    vpor 8(%rsp), %xmm3, %xmm8
    vpor -200(%rbp), %xmm8, %xmm7
    vpor (%r12), %xmm7, %xmm11
    vpor 0x40(%r13), %xmm11, %xmm1
    vpor (%rax,%r9,8), %xmm1, %xmm14
    vpor 16(%r15,%rcx,2), %xmm14, %xmm3
    vpor -4(%rdx,%r14,4), %xmm3, %xmm8
    vpor %ymm3, %ymm0, %ymm7
    vpor %ymm15, %ymm2, %ymm1
    vpor %ymm1, %ymm14, %ymm3
    vpor %ymm12, %ymm8, %ymm7
    vpor %ymm7, %ymm2, %ymm9
    vpor %ymm9, %ymm6, %ymm12
    vpor %ymm3, %ymm8, %ymm15
    vpor %ymm15, %ymm11, %ymm9
    vpor (%rax), %ymm14, %ymm3
    vpor 8(%rsp), %ymm3, %ymm8
    vpor -200(%rbp), %ymm8, %ymm7
    vpor (%r12), %ymm7, %ymm11
    vpor 0x40(%r13), %ymm11, %ymm1
    vpor (%rax,%r9,8), %ymm1, %ymm14
    vpor 16(%r15,%rcx,2), %ymm14, %ymm3
    vpor -4(%rdx,%r14,4), %ymm3, %ymm8
    vpxor %xmm1, %xmm6, %xmm3
    vpxor %xmm12, %xmm0, %xmm7
    vpxor %xmm7, %xmm11, %xmm1
    vpxor %xmm9, %xmm14, %xmm3
    vpxor %xmm3, %xmm0, %xmm15
    vpxor %xmm15, %xmm2, %xmm9
    vpxor %xmm1, %xmm14, %xmm12
    vpxor %xmm12, %xmm8, %xmm15
    vpxor (%rax), %xmm14, %xmm3
    vpxor 8(%rsp), %xmm3, %xmm8
    vpxor -200(%rbp), %xmm8, %xmm7
    vpxor (%r12), %xmm7, %xmm11
    vpxor 0x40(%r13), %xmm11, %xmm1
    vpxor (%rax,%r9,8), %xmm1, %xmm14
    vpxor 16(%r15,%rcx,2), %xmm14, %xmm3
    vpxor -4(%rdx,%r14,4), %xmm3, %xmm8
    vpxor %ymm7, %ymm2, %ymm1
    vpxor %ymm9, %ymm6, %ymm3
    vpxor %ymm3, %ymm8, %ymm7
    vpxor %ymm15, %ymm11, %ymm1
    vpxor %ymm1, %ymm6, %ymm12
    vpxor %ymm12, %ymm0, %ymm15
    vpxor %ymm7, %ymm11, %ymm9
    vpxor %ymm9, %ymm14, %ymm12
    vpxor (%rax), %ymm14, %ymm3
    vpxor 8(%rsp), %ymm3, %ymm8
    vpxor -200(%rbp), %ymm8, %ymm7
    vpxor (%r12), %ymm7, %ymm11
    vpxor 0x40(%r13), %ymm11, %ymm1
    vpxor (%rax,%r9,8), %ymm1, %ymm14
    vpxor 16(%r15,%rcx,2), %ymm14, %ymm3
    vpxor -4(%rdx,%r14,4), %ymm3, %ymm8
    vaddpd %xmm3, %xmm0, %xmm7
    vaddpd %xmm15, %xmm2, %xmm1
    vaddpd %xmm1, %xmm14, %xmm3
    vaddpd %xmm12, %xmm8, %xmm7
    vaddpd %xmm7, %xmm2, %xmm9
    vaddpd %xmm9, %xmm6, %xmm12
    vaddpd %xmm3, %xmm8, %xmm15
    vaddpd %xmm15, %xmm11, %xmm9
    vaddpd (%rax), %xmm14, %xmm3
    vaddpd 8(%rsp), %xmm3, %xmm8
    vaddpd -200(%rbp), %xmm8, %xmm7
    vaddpd (%r12), %xmm7, %xmm11
    vaddpd 0x40(%r13), %xmm11, %xmm1
    vaddpd (%rax,%r9,8), %xmm1, %xmm14
    vaddpd 16(%r15,%rcx,2), %xmm14, %xmm3
    vaddpd -4(%rdx,%r14,4), %xmm3, %xmm8
    vaddpd %ymm1, %ymm6, %ymm3
    vaddpd %ymm12, %ymm0, %ymm7
    vaddpd %ymm7, %ymm11, %ymm1
    vaddpd %ymm9, %ymm14, %ymm3
    vaddpd %ymm3, %ymm0, %ymm15
    vaddpd %ymm15, %ymm2, %ymm9
    vaddpd %ymm1, %ymm14, %ymm12
    vaddpd %ymm12, %ymm8, %ymm15
    vaddpd (%rax), %ymm14, %ymm3
    vaddpd 8(%rsp), %ymm3, %ymm8
    vaddpd -200(%rbp), %ymm8, %ymm7
    vaddpd (%r12), %ymm7, %ymm11
    vaddpd 0x40(%r13), %ymm11, %ymm1
    vaddpd (%rax,%r9,8), %ymm1, %ymm14
    vaddpd 16(%r15,%rcx,2), %ymm14, %ymm3
    vaddpd -4(%rdx,%r14,4), %ymm3, %ymm8
    vmulpd %xmm7, %xmm2, %xmm1
    vmulpd %xmm9, %xmm6, %xmm3
    vmulpd %xmm3, %xmm8, %xmm7
    vmulpd %xmm15, %xmm11, %xmm1
    vmulpd %xmm1, %xmm6, %xmm12
    vmulpd %xmm12, %xmm0, %xmm15
    vmulpd %xmm7, %xmm11, %xmm9
    vmulpd %xmm9, %xmm14, %xmm12
    vmulpd (%rax), %xmm14, %xmm3
    vmulpd 8(%rsp), %xmm3, %xmm8
    vmulpd -200(%rbp), %xmm8, %xmm7
    vmulpd (%r12), %xmm7, %xmm11
    vmulpd 0x40(%r13), %xmm11, %xmm1
    vmulpd (%rax,%r9,8), %xmm1, %xmm14
    vmulpd 16(%r15,%rcx,2), %xmm14, %xmm3
    vmulpd -4(%rdx,%r14,4), %xmm3, %xmm8
    vmulpd %ymm3, %ymm0, %ymm7
    vmulpd %ymm15, %ymm2, %ymm1
    vmulpd %ymm1, %ymm14, %ymm3
    vmulpd %ymm12, %ymm8, %ymm7
    vmulpd %ymm7, %ymm2, %ymm9
    vmulpd %ymm9, %ymm6, %ymm12
    vmulpd %ymm3, %ymm8, %ymm15
    vmulpd %ymm15, %ymm11, %ymm9
    vmulpd (%rax), %ymm14, %ymm3
    vmulpd 8(%rsp), %ymm3, %ymm8
    vmulpd -200(%rbp), %ymm8, %ymm7
    vmulpd (%r12), %ymm7, %ymm11
    vmulpd 0x40(%r13), %ymm11, %ymm1
    vmulpd (%rax,%r9,8), %ymm1, %ymm14
    vmulpd 16(%r15,%rcx,2), %ymm14, %ymm3
    vmulpd -4(%rdx,%r14,4), %ymm3, %ymm8
    vandpd %xmm1, %xmm6, %xmm3
    vandpd %xmm12, %xmm0, %xmm7
    vandpd %xmm7, %xmm11, %xmm1
    vandpd %xmm9, %xmm14, %xmm3
    vandpd %xmm3, %xmm0, %xmm15
    vandpd %xmm15, %xmm2, %xmm9
    vandpd %xmm1, %xmm14, %xmm12
    vandpd %xmm12, %xmm8, %xmm15
    vandpd (%rax), %xmm14, %xmm3
    vandpd 8(%rsp), %xmm3, %xmm8
    vandpd -200(%rbp), %xmm8, %xmm7
    vandpd (%r12), %xmm7, %xmm11
    vandpd 0x40(%r13), %xmm11, %xmm1
    vandpd (%rax,%r9,8), %xmm1, %xmm14
    vandpd 16(%r15,%rcx,2), %xmm14, %xmm3
    vandpd -4(%rdx,%r14,4), %xmm3, %xmm8
    vandpd %ymm7, %ymm2, %ymm1
    vandpd %ymm9, %ymm6, %ymm3
    vandpd %ymm3, %ymm8, %ymm7
    vandpd %ymm15, %ymm11, %ymm1
    vandpd %ymm1, %ymm6, %ymm12
    vandpd %ymm12, %ymm0, %ymm15
    vandpd %ymm7, %ymm11, %ymm9
    vandpd %ymm9, %ymm14, %ymm12
    vandpd (%rax), %ymm14, %ymm3
    vandpd 8(%rsp), %ymm3, %ymm8
    vandpd -200(%rbp), %ymm8, %ymm7
    vandpd (%r12), %ymm7, %ymm11
    vandpd 0x40(%r13), %ymm11, %ymm1
    vandpd (%rax,%r9,8), %ymm1, %ymm14
    vandpd 16(%r15,%rcx,2), %ymm14, %ymm3
    vandpd -4(%rdx,%r14,4), %ymm3, %ymm8
    vorpd %xmm3, %xmm0, %xmm7
    vorpd %xmm15, %xmm2, %xmm1
    vorpd %xmm1, %xmm14, %xmm3
    vorpd %xmm12, %xmm8, %xmm7
    vorpd %xmm7, %xmm2, %xmm9
    vorpd %xmm9, %xmm6, %xmm12
    vorpd %xmm3, %xmm8, %xmm15
    vorpd %xmm15, %xmm11, %xmm9
    vorpd (%rax), %xmm14, %xmm3
    vorpd 8(%rsp), %xmm3, %xmm8
    vorpd -200(%rbp), %xmm8, %xmm7
    vorpd (%r12), %xmm7, %xmm11
    vorpd 0x40(%r13), %xmm11, %xmm1
    vorpd (%rax,%r9,8), %xmm1, %xmm14
    vorpd 16(%r15,%rcx,2), %xmm14, %xmm3
    vorpd -4(%rdx,%r14,4), %xmm3, %xmm8
    vorpd %ymm1, %ymm6, %ymm3
    vorpd %ymm12, %ymm0, %ymm7
    vorpd %ymm7, %ymm11, %ymm1
    vorpd %ymm9, %ymm14, %ymm3
    vorpd %ymm3, %ymm0, %ymm15
    vorpd %ymm15, %ymm2, %ymm9
    vorpd %ymm1, %ymm14, %ymm12
    vorpd %ymm12, %ymm8, %ymm15
    vorpd (%rax), %ymm14, %ymm3
    vorpd 8(%rsp), %ymm3, %ymm8
    vorpd -200(%rbp), %ymm8, %ymm7
    vorpd (%r12), %ymm7, %ymm11
    vorpd 0x40(%r13), %ymm11, %ymm1
    vorpd (%rax,%r9,8), %ymm1, %ymm14
    vorpd 16(%r15,%rcx,2), %ymm14, %ymm3
    vorpd -4(%rdx,%r14,4), %ymm3, %ymm8
    vxorpd %xmm7, %xmm2, %xmm1
    vxorpd %xmm9, %xmm6, %xmm3
    vxorpd %xmm3, %xmm8, %xmm7
    vxorpd %xmm15, %xmm11, %xmm1
    vxorpd %xmm1, %xmm6, %xmm12
    vxorpd %xmm12, %xmm0, %xmm15
    vxorpd %xmm7, %xmm11, %xmm9
    vxorpd %xmm9, %xmm14, %xmm12
    vxorpd (%rax), %xmm14, %xmm3
    vxorpd 8(%rsp), %xmm3, %xmm8
    vxorpd -200(%rbp), %xmm8, %xmm7
    vxorpd (%r12), %xmm7, %xmm11
    vxorpd 0x40(%r13), %xmm11, %xmm1
    vxorpd (%rax,%r9,8), %xmm1, %xmm14
    vxorpd 16(%r15,%rcx,2), %xmm14, %xmm3
    vxorpd -4(%rdx,%r14,4), %xmm3, %xmm8
    vxorpd %ymm3, %ymm0, %ymm7
    vxorpd %ymm15, %ymm2, %ymm1
    vxorpd %ymm1, %ymm14, %ymm3
    vxorpd %ymm12, %ymm8, %ymm7
    vxorpd %ymm7, %ymm2, %ymm9
    vxorpd %ymm9, %ymm6, %ymm12
    vxorpd %ymm3, %ymm8, %ymm15
    vxorpd %ymm15, %ymm11, %ymm9
    vxorpd (%rax), %ymm14, %ymm3
    vxorpd 8(%rsp), %ymm3, %ymm8
    vxorpd -200(%rbp), %ymm8, %ymm7
    vxorpd (%r12), %ymm7, %ymm11
    vxorpd 0x40(%r13), %ymm11, %ymm1
    vxorpd (%rax,%r9,8), %ymm1, %ymm14
    vxorpd 16(%r15,%rcx,2), %ymm14, %ymm3
    vxorpd -4(%rdx,%r14,4), %ymm3, %ymm8
    vaddps %xmm1, %xmm6, %xmm3
    vaddps %xmm12, %xmm0, %xmm7
    vaddps %xmm7, %xmm11, %xmm1
    vaddps %xmm9, %xmm14, %xmm3
    vaddps %xmm3, %xmm0, %xmm15
    vaddps %xmm15, %xmm2, %xmm9
    vaddps %xmm1, %xmm14, %xmm12
    vaddps %xmm12, %xmm8, %xmm15
    vaddps (%rax), %xmm14, %xmm3
    vaddps 8(%rsp), %xmm3, %xmm8
    vaddps -200(%rbp), %xmm8, %xmm7
    vaddps (%r12), %xmm7, %xmm11
    vaddps 0x40(%r13), %xmm11, %xmm1
    vaddps (%rax,%r9,8), %xmm1, %xmm14
    vaddps 16(%r15,%rcx,2), %xmm14, %xmm3
    vaddps -4(%rdx,%r14,4), %xmm3, %xmm8
    vaddps %ymm7, %ymm2, %ymm1
    vaddps %ymm9, %ymm6, %ymm3
    vaddps %ymm3, %ymm8, %ymm7
    vaddps %ymm15, %ymm11, %ymm1
    vaddps %ymm1, %ymm6, %ymm12
    vaddps %ymm12, %ymm0, %ymm15
    vaddps %ymm7, %ymm11, %ymm9
    vaddps %ymm9, %ymm14, %ymm12
    vaddps (%rax), %ymm14, %ymm3
    vaddps 8(%rsp), %ymm3, %ymm8
    vaddps -200(%rbp), %ymm8, %ymm7
    vaddps (%r12), %ymm7, %ymm11
    vaddps 0x40(%r13), %ymm11, %ymm1
    vaddps (%rax,%r9,8), %ymm1, %ymm14
    vaddps 16(%r15,%rcx,2), %ymm14, %ymm3
    vaddps -4(%rdx,%r14,4), %ymm3, %ymm8
    vmulps %xmm3, %xmm0, %xmm7
    vmulps %xmm15, %xmm2, %xmm1
    vmulps %xmm1, %xmm14, %xmm3
    vmulps %xmm12, %xmm8, %xmm7
    vmulps %xmm7, %xmm2, %xmm9
    vmulps %xmm9, %xmm6, %xmm12
    vmulps %xmm3, %xmm8, %xmm15
    vmulps %xmm15, %xmm11, %xmm9
    vmulps (%rax), %xmm14, %xmm3
    vmulps 8(%rsp), %xmm3, %xmm8
    vmulps -200(%rbp), %xmm8, %xmm7
    vmulps (%r12), %xmm7, %xmm11
    vmulps 0x40(%r13), %xmm11, %xmm1
    vmulps (%rax,%r9,8), %xmm1, %xmm14
    vmulps 16(%r15,%rcx,2), %xmm14, %xmm3
    vmulps -4(%rdx,%r14,4), %xmm3, %xmm8
    vmulps %ymm1, %ymm6, %ymm3
    vmulps %ymm12, %ymm0, %ymm7
    vmulps %ymm7, %ymm11, %ymm1
    vmulps %ymm9, %ymm14, %ymm3
    vmulps %ymm3, %ymm0, %ymm15
    vmulps %ymm15, %ymm2, %ymm9
    vmulps %ymm1, %ymm14, %ymm12
    vmulps %ymm12, %ymm8, %ymm15
    vmulps (%rax), %ymm14, %ymm3
    vmulps 8(%rsp), %ymm3, %ymm8
    vmulps -200(%rbp), %ymm8, %ymm7
    vmulps (%r12), %ymm7, %ymm11
    vmulps 0x40(%r13), %ymm11, %ymm1
    vmulps (%rax,%r9,8), %ymm1, %ymm14
    vmulps 16(%r15,%rcx,2), %ymm14, %ymm3
    vmulps -4(%rdx,%r14,4), %ymm3, %ymm8
    vandps %xmm7, %xmm2, %xmm1
    vandps %xmm9, %xmm6, %xmm3
    vandps %xmm3, %xmm8, %xmm7
    vandps %xmm15, %xmm11, %xmm1
    vandps %xmm1, %xmm6, %xmm12
    vandps %xmm12, %xmm0, %xmm15
    vandps %xmm7, %xmm11, %xmm9
    vandps %xmm9, %xmm14, %xmm12
    vandps (%rax), %xmm14, %xmm3
    vandps 8(%rsp), %xmm3, %xmm8
    vandps -200(%rbp), %xmm8, %xmm7
    vandps (%r12), %xmm7, %xmm11
    vandps 0x40(%r13), %xmm11, %xmm1
    vandps (%rax,%r9,8), %xmm1, %xmm14
    vandps 16(%r15,%rcx,2), %xmm14, %xmm3
    vandps -4(%rdx,%r14,4), %xmm3, %xmm8
    vandps %ymm3, %ymm0, %ymm7
    vandps %ymm15, %ymm2, %ymm1
    vandps %ymm1, %ymm14, %ymm3
    vandps %ymm12, %ymm8, %ymm7
    vandps %ymm7, %ymm2, %ymm9
    vandps %ymm9, %ymm6, %ymm12
    vandps %ymm3, %ymm8, %ymm15
    vandps %ymm15, %ymm11, %ymm9
    vandps (%rax), %ymm14, %ymm3
    vandps 8(%rsp), %ymm3, %ymm8
    vandps -200(%rbp), %ymm8, %ymm7
    vandps (%r12), %ymm7, %ymm11
    vandps 0x40(%r13), %ymm11, %ymm1
    vandps (%rax,%r9,8), %ymm1, %ymm14
    vandps 16(%r15,%rcx,2), %ymm14, %ymm3
    vandps -4(%rdx,%r14,4), %ymm3, %ymm8
    vorps %xmm1, %xmm6, %xmm3
    vorps %xmm12, %xmm0, %xmm7
    vorps %xmm7, %xmm11, %xmm1
    vorps %xmm9, %xmm14, %xmm3
    vorps %xmm3, %xmm0, %xmm15
    vorps %xmm15, %xmm2, %xmm9
    vorps %xmm1, %xmm14, %xmm12
    vorps %xmm12, %xmm8, %xmm15
    vorps (%rax), %xmm14, %xmm3
    vorps 8(%rsp), %xmm3, %xmm8
    vorps -200(%rbp), %xmm8, %xmm7
    vorps (%r12), %xmm7, %xmm11
    vorps 0x40(%r13), %xmm11, %xmm1
    vorps (%rax,%r9,8), %xmm1, %xmm14
    vorps 16(%r15,%rcx,2), %xmm14, %xmm3
    vorps -4(%rdx,%r14,4), %xmm3, %xmm8
    vorps %ymm7, %ymm2, %ymm1
    vorps %ymm9, %ymm6, %ymm3
    vorps %ymm3, %ymm8, %ymm7
    vorps %ymm15, %ymm11, %ymm1
    vorps %ymm1, %ymm6, %ymm12
    vorps %ymm12, %ymm0, %ymm15
    vorps %ymm7, %ymm11, %ymm9
    vorps %ymm9, %ymm14, %ymm12
    vorps (%rax), %ymm14, %ymm3
    vorps 8(%rsp), %ymm3, %ymm8
    vorps -200(%rbp), %ymm8, %ymm7
    vorps (%r12), %ymm7, %ymm11
    vorps 0x40(%r13), %ymm11, %ymm1
    vorps (%rax,%r9,8), %ymm1, %ymm14
    vorps 16(%r15,%rcx,2), %ymm14, %ymm3
    vorps -4(%rdx,%r14,4), %ymm3, %ymm8
    vxorps %xmm3, %xmm0, %xmm7
    vxorps %xmm15, %xmm2, %xmm1
    vxorps %xmm1, %xmm14, %xmm3
    vxorps %xmm12, %xmm8, %xmm7
    vxorps %xmm7, %xmm2, %xmm9
    vxorps %xmm9, %xmm6, %xmm12
    vxorps %xmm3, %xmm8, %xmm15
    vxorps %xmm15, %xmm11, %xmm9
    vxorps (%rax), %xmm14, %xmm3
    vxorps 8(%rsp), %xmm3, %xmm8
    vxorps -200(%rbp), %xmm8, %xmm7
    vxorps (%r12), %xmm7, %xmm11
    vxorps 0x40(%r13), %xmm11, %xmm1
    vxorps (%rax,%r9,8), %xmm1, %xmm14
    vxorps 16(%r15,%rcx,2), %xmm14, %xmm3
    vxorps -4(%rdx,%r14,4), %xmm3, %xmm8
    vxorps %ymm1, %ymm6, %ymm3
    vxorps %ymm12, %ymm0, %ymm7
    vxorps %ymm7, %ymm11, %ymm1
    vxorps %ymm9, %ymm14, %ymm3
    vxorps %ymm3, %ymm0, %ymm15
    vxorps %ymm15, %ymm2, %ymm9
    vxorps %ymm1, %ymm14, %ymm12
    vxorps %ymm12, %ymm8, %ymm15
    vxorps (%rax), %ymm14, %ymm3
    vxorps 8(%rsp), %ymm3, %ymm8
    vxorps -200(%rbp), %ymm8, %ymm7
    vxorps (%r12), %ymm7, %ymm11
    vxorps 0x40(%r13), %ymm11, %ymm1
    vxorps (%rax,%r9,8), %ymm1, %ymm14
    vxorps 16(%r15,%rcx,2), %ymm14, %ymm3
    vxorps -4(%rdx,%r14,4), %ymm3, %ymm8
    vpsubb %xmm7, %xmm2, %xmm1
    vpsubb %xmm9, %xmm6, %xmm3
    vpsubb %xmm3, %xmm8, %xmm7
    vpsubb %xmm15, %xmm11, %xmm1
    vpsubb %xmm1, %xmm6, %xmm12
    vpsubb %xmm12, %xmm0, %xmm15
    vpsubb %xmm7, %xmm11, %xmm9
    vpsubb %xmm9, %xmm14, %xmm12
    vpsubb (%rax), %xmm14, %xmm3
    vpsubb 8(%rsp), %xmm3, %xmm8
    vpsubb -200(%rbp), %xmm8, %xmm7
    vpsubb (%r12), %xmm7, %xmm11
    vpsubb 0x40(%r13), %xmm11, %xmm1
    vpsubb (%rax,%r9,8), %xmm1, %xmm14
    vpsubb 16(%r15,%rcx,2), %xmm14, %xmm3
    vpsubb -4(%rdx,%r14,4), %xmm3, %xmm8
    vpsubb %ymm3, %ymm0, %ymm7
    vpsubb %ymm15, %ymm2, %ymm1
    vpsubb %ymm1, %ymm14, %ymm3
    vpsubb %ymm12, %ymm8, %ymm7
    vpsubb %ymm7, %ymm2, %ymm9
    vpsubb %ymm9, %ymm6, %ymm12
    vpsubb %ymm3, %ymm8, %ymm15
    vpsubb %ymm15, %ymm11, %ymm9
    vpsubb (%rax), %ymm14, %ymm3
    vpsubb 8(%rsp), %ymm3, %ymm8
    vpsubb -200(%rbp), %ymm8, %ymm7
    vpsubb (%r12), %ymm7, %ymm11
    vpsubb 0x40(%r13), %ymm11, %ymm1
    vpsubb (%rax,%r9,8), %ymm1, %ymm14
    vpsubb 16(%r15,%rcx,2), %ymm14, %ymm3
    vpsubb -4(%rdx,%r14,4), %ymm3, %ymm8
    vpsubw %xmm1, %xmm6, %xmm3
    vpsubw %xmm12, %xmm0, %xmm7
    vpsubw %xmm7, %xmm11, %xmm1
    vpsubw %xmm9, %xmm14, %xmm3
    vpsubw %xmm3, %xmm0, %xmm15
    vpsubw %xmm15, %xmm2, %xmm9
    vpsubw %xmm1, %xmm14, %xmm12
    vpsubw %xmm12, %xmm8, %xmm15
    vpsubw (%rax), %xmm14, %xmm3
    vpsubw 8(%rsp), %xmm3, %xmm8
    vpsubw -200(%rbp), %xmm8, %xmm7
    vpsubw (%r12), %xmm7, %xmm11
    vpsubw 0x40(%r13), %xmm11, %xmm1
    vpsubw (%rax,%r9,8), %xmm1, %xmm14
    vpsubw 16(%r15,%rcx,2), %xmm14, %xmm3
    vpsubw -4(%rdx,%r14,4), %xmm3, %xmm8
    vpsubw %ymm7, %ymm2, %ymm1
    vpsubw %ymm9, %ymm6, %ymm3
    vpsubw %ymm3, %ymm8, %ymm7
    vpsubw %ymm15, %ymm11, %ymm1
    vpsubw %ymm1, %ymm6, %ymm12
    vpsubw %ymm12, %ymm0, %ymm15
    vpsubw %ymm7, %ymm11, %ymm9
    vpsubw %ymm9, %ymm14, %ymm12
    vpsubw (%rax), %ymm14, %ymm3
    vpsubw 8(%rsp), %ymm3, %ymm8
    vpsubw -200(%rbp), %ymm8, %ymm7
    vpsubw (%r12), %ymm7, %ymm11
    vpsubw 0x40(%r13), %ymm11, %ymm1
    vpsubw (%rax,%r9,8), %ymm1, %ymm14
    vpsubw 16(%r15,%rcx,2), %ymm14, %ymm3
    vpsubw -4(%rdx,%r14,4), %ymm3, %ymm8
    vpsubd %xmm3, %xmm0, %xmm7
    vpsubd %xmm15, %xmm2, %xmm1
    vpsubd %xmm1, %xmm14, %xmm3
    vpsubd %xmm12, %xmm8, %xmm7
    vpsubd %xmm7, %xmm2, %xmm9
    vpsubd %xmm9, %xmm6, %xmm12
    vpsubd %xmm3, %xmm8, %xmm15
    vpsubd %xmm15, %xmm11, %xmm9
    vpsubd (%rax), %xmm14, %xmm3
    vpsubd 8(%rsp), %xmm3, %xmm8
    vpsubd -200(%rbp), %xmm8, %xmm7
    vpsubd (%r12), %xmm7, %xmm11
    vpsubd 0x40(%r13), %xmm11, %xmm1
    vpsubd (%rax,%r9,8), %xmm1, %xmm14
    vpsubd 16(%r15,%rcx,2), %xmm14, %xmm3
    vpsubd -4(%rdx,%r14,4), %xmm3, %xmm8
    vpsubd %ymm1, %ymm6, %ymm3
    vpsubd %ymm12, %ymm0, %ymm7
    vpsubd %ymm7, %ymm11, %ymm1
    vpsubd %ymm9, %ymm14, %ymm3
    vpsubd %ymm3, %ymm0, %ymm15
    vpsubd %ymm15, %ymm2, %ymm9
    vpsubd %ymm1, %ymm14, %ymm12
    vpsubd %ymm12, %ymm8, %ymm15
    vpsubd (%rax), %ymm14, %ymm3
    vpsubd 8(%rsp), %ymm3, %ymm8
    vpsubd -200(%rbp), %ymm8, %ymm7
    vpsubd (%r12), %ymm7, %ymm11
    vpsubd 0x40(%r13), %ymm11, %ymm1
    vpsubd (%rax,%r9,8), %ymm1, %ymm14
    vpsubd 16(%r15,%rcx,2), %ymm14, %ymm3
    vpsubd -4(%rdx,%r14,4), %ymm3, %ymm8
    vpsubq %xmm7, %xmm2, %xmm1
    vpsubq %xmm9, %xmm6, %xmm3
    vpsubq %xmm3, %xmm8, %xmm7
    vpsubq %xmm15, %xmm11, %xmm1
    vpsubq %xmm1, %xmm6, %xmm12
    vpsubq %xmm12, %xmm0, %xmm15
    vpsubq %xmm7, %xmm11, %xmm9
    vpsubq %xmm9, %xmm14, %xmm12
    vpsubq (%rax), %xmm14, %xmm3
    vpsubq 8(%rsp), %xmm3, %xmm8
    vpsubq -200(%rbp), %xmm8, %xmm7
    vpsubq (%r12), %xmm7, %xmm11
    vpsubq 0x40(%r13), %xmm11, %xmm1
    vpsubq (%rax,%r9,8), %xmm1, %xmm14
    vpsubq 16(%r15,%rcx,2), %xmm14, %xmm3
    vpsubq -4(%rdx,%r14,4), %xmm3, %xmm8
    vpsubq %ymm3, %ymm0, %ymm7
    vpsubq %ymm15, %ymm2, %ymm1
    vpsubq %ymm1, %ymm14, %ymm3
    vpsubq %ymm12, %ymm8, %ymm7
    vpsubq %ymm7, %ymm2, %ymm9
    vpsubq %ymm9, %ymm6, %ymm12
    vpsubq %ymm3, %ymm8, %ymm15
    vpsubq %ymm15, %ymm11, %ymm9
    vpsubq (%rax), %ymm14, %ymm3
    vpsubq 8(%rsp), %ymm3, %ymm8
    vpsubq -200(%rbp), %ymm8, %ymm7
    vpsubq (%r12), %ymm7, %ymm11
    vpsubq 0x40(%r13), %ymm11, %ymm1
    vpsubq (%rax,%r9,8), %ymm1, %ymm14
    vpsubq 16(%r15,%rcx,2), %ymm14, %ymm3
    vpsubq -4(%rdx,%r14,4), %ymm3, %ymm8
    vpsubsb %xmm1, %xmm6, %xmm3
    vpsubsb %xmm12, %xmm0, %xmm7
    vpsubsb %xmm7, %xmm11, %xmm1
    vpsubsb %xmm9, %xmm14, %xmm3
    vpsubsb %xmm3, %xmm0, %xmm15
    vpsubsb %xmm15, %xmm2, %xmm9
    vpsubsb %xmm1, %xmm14, %xmm12
    vpsubsb %xmm12, %xmm8, %xmm15
    vpsubsb (%rax), %xmm14, %xmm3
    vpsubsb 8(%rsp), %xmm3, %xmm8
    vpsubsb -200(%rbp), %xmm8, %xmm7
    vpsubsb (%r12), %xmm7, %xmm11
    vpsubsb 0x40(%r13), %xmm11, %xmm1
    vpsubsb (%rax,%r9,8), %xmm1, %xmm14
    vpsubsb 16(%r15,%rcx,2), %xmm14, %xmm3
    vpsubsb -4(%rdx,%r14,4), %xmm3, %xmm8
    vpsubsb %ymm7, %ymm2, %ymm1
    vpsubsb %ymm9, %ymm6, %ymm3
    vpsubsb %ymm3, %ymm8, %ymm7
    vpsubsb %ymm15, %ymm11, %ymm1
    vpsubsb %ymm1, %ymm6, %ymm12
    vpsubsb %ymm12, %ymm0, %ymm15
    vpsubsb %ymm7, %ymm11, %ymm9
    vpsubsb %ymm9, %ymm14, %ymm12
    vpsubsb (%rax), %ymm14, %ymm3
    vpsubsb 8(%rsp), %ymm3, %ymm8
    vpsubsb -200(%rbp), %ymm8, %ymm7
    vpsubsb (%r12), %ymm7, %ymm11
    vpsubsb 0x40(%r13), %ymm11, %ymm1
    vpsubsb (%rax,%r9,8), %ymm1, %ymm14
    vpsubsb 16(%r15,%rcx,2), %ymm14, %ymm3
    vpsubsb -4(%rdx,%r14,4), %ymm3, %ymm8
    vpsubsw %xmm3, %xmm0, %xmm7
    vpsubsw %xmm15, %xmm2, %xmm1
    vpsubsw %xmm1, %xmm14, %xmm3
    vpsubsw %xmm12, %xmm8, %xmm7
    vpsubsw %xmm7, %xmm2, %xmm9
    vpsubsw %xmm9, %xmm6, %xmm12
    vpsubsw %xmm3, %xmm8, %xmm15
    vpsubsw %xmm15, %xmm11, %xmm9
    vpsubsw (%rax), %xmm14, %xmm3
    vpsubsw 8(%rsp), %xmm3, %xmm8
    vpsubsw -200(%rbp), %xmm8, %xmm7
    vpsubsw (%r12), %xmm7, %xmm11
    vpsubsw 0x40(%r13), %xmm11, %xmm1
    vpsubsw (%rax,%r9,8), %xmm1, %xmm14
    vpsubsw 16(%r15,%rcx,2), %xmm14, %xmm3
    vpsubsw -4(%rdx,%r14,4), %xmm3, %xmm8
    vpsubsw %ymm1, %ymm6, %ymm3
    vpsubsw %ymm12, %ymm0, %ymm7
    vpsubsw %ymm7, %ymm11, %ymm1
    vpsubsw %ymm9, %ymm14, %ymm3
    vpsubsw %ymm3, %ymm0, %ymm15
    vpsubsw %ymm15, %ymm2, %ymm9
    vpsubsw %ymm1, %ymm14, %ymm12
    vpsubsw %ymm12, %ymm8, %ymm15
    vpsubsw (%rax), %ymm14, %ymm3
    vpsubsw 8(%rsp), %ymm3, %ymm8
    vpsubsw -200(%rbp), %ymm8, %ymm7
    vpsubsw (%r12), %ymm7, %ymm11
    vpsubsw 0x40(%r13), %ymm11, %ymm1
    vpsubsw (%rax,%r9,8), %ymm1, %ymm14
    vpsubsw 16(%r15,%rcx,2), %ymm14, %ymm3
    vpsubsw -4(%rdx,%r14,4), %ymm3, %ymm8
    vpsubusb %xmm7, %xmm2, %xmm1
    vpsubusb %xmm9, %xmm6, %xmm3
    vpsubusb %xmm3, %xmm8, %xmm7
    vpsubusb %xmm15, %xmm11, %xmm1
    vpsubusb %xmm1, %xmm6, %xmm12
    vpsubusb %xmm12, %xmm0, %xmm15
    vpsubusb %xmm7, %xmm11, %xmm9
    vpsubusb %xmm9, %xmm14, %xmm12
    vpsubusb (%rax), %xmm14, %xmm3
    vpsubusb 8(%rsp), %xmm3, %xmm8
    vpsubusb -200(%rbp), %xmm8, %xmm7
    vpsubusb (%r12), %xmm7, %xmm11
    vpsubusb 0x40(%r13), %xmm11, %xmm1
    vpsubusb (%rax,%r9,8), %xmm1, %xmm14
    vpsubusb 16(%r15,%rcx,2), %xmm14, %xmm3
    vpsubusb -4(%rdx,%r14,4), %xmm3, %xmm8
    vpsubusb %ymm3, %ymm0, %ymm7
    vpsubusb %ymm15, %ymm2, %ymm1
    vpsubusb %ymm1, %ymm14, %ymm3
    vpsubusb %ymm12, %ymm8, %ymm7
    vpsubusb %ymm7, %ymm2, %ymm9
    vpsubusb %ymm9, %ymm6, %ymm12
    vpsubusb %ymm3, %ymm8, %ymm15
    vpsubusb %ymm15, %ymm11, %ymm9
    vpsubusb (%rax), %ymm14, %ymm3
    vpsubusb 8(%rsp), %ymm3, %ymm8
    vpsubusb -200(%rbp), %ymm8, %ymm7
    vpsubusb (%r12), %ymm7, %ymm11
    vpsubusb 0x40(%r13), %ymm11, %ymm1
    vpsubusb (%rax,%r9,8), %ymm1, %ymm14
    vpsubusb 16(%r15,%rcx,2), %ymm14, %ymm3
    vpsubusb -4(%rdx,%r14,4), %ymm3, %ymm8
    vpsubusw %xmm1, %xmm6, %xmm3
    vpsubusw %xmm12, %xmm0, %xmm7
    vpsubusw %xmm7, %xmm11, %xmm1
    vpsubusw %xmm9, %xmm14, %xmm3
    vpsubusw %xmm3, %xmm0, %xmm15
    vpsubusw %xmm15, %xmm2, %xmm9
    vpsubusw %xmm1, %xmm14, %xmm12
    vpsubusw %xmm12, %xmm8, %xmm15
    vpsubusw (%rax), %xmm14, %xmm3
    vpsubusw 8(%rsp), %xmm3, %xmm8
    vpsubusw -200(%rbp), %xmm8, %xmm7
    vpsubusw (%r12), %xmm7, %xmm11
    vpsubusw 0x40(%r13), %xmm11, %xmm1
    vpsubusw (%rax,%r9,8), %xmm1, %xmm14
    vpsubusw 16(%r15,%rcx,2), %xmm14, %xmm3
    vpsubusw -4(%rdx,%r14,4), %xmm3, %xmm8
    vpsubusw %ymm7, %ymm2, %ymm1
    vpsubusw %ymm9, %ymm6, %ymm3
    vpsubusw %ymm3, %ymm8, %ymm7
    vpsubusw %ymm15, %ymm11, %ymm1
    vpsubusw %ymm1, %ymm6, %ymm12
    vpsubusw %ymm12, %ymm0, %ymm15
    vpsubusw %ymm7, %ymm11, %ymm9
    vpsubusw %ymm9, %ymm14, %ymm12
    vpsubusw (%rax), %ymm14, %ymm3
    vpsubusw 8(%rsp), %ymm3, %ymm8
    vpsubusw -200(%rbp), %ymm8, %ymm7
    vpsubusw (%r12), %ymm7, %ymm11
    vpsubusw 0x40(%r13), %ymm11, %ymm1
    vpsubusw (%rax,%r9,8), %ymm1, %ymm14
    vpsubusw 16(%r15,%rcx,2), %ymm14, %ymm3
    vpsubusw -4(%rdx,%r14,4), %ymm3, %ymm8
    vpcmpgtb %xmm3, %xmm0, %xmm7
    vpcmpgtb %xmm15, %xmm2, %xmm1
    vpcmpgtb %xmm1, %xmm14, %xmm3
    vpcmpgtb %xmm12, %xmm8, %xmm7
    vpcmpgtb %xmm7, %xmm2, %xmm9
    vpcmpgtb %xmm9, %xmm6, %xmm12
    vpcmpgtb %xmm3, %xmm8, %xmm15
    vpcmpgtb %xmm15, %xmm11, %xmm9
    vpcmpgtb (%rax), %xmm14, %xmm3
    vpcmpgtb 8(%rsp), %xmm3, %xmm8
    vpcmpgtb -200(%rbp), %xmm8, %xmm7
    vpcmpgtb (%r12), %xmm7, %xmm11
    vpcmpgtb 0x40(%r13), %xmm11, %xmm1
    vpcmpgtb (%rax,%r9,8), %xmm1, %xmm14
    vpcmpgtb 16(%r15,%rcx,2), %xmm14, %xmm3
    vpcmpgtb -4(%rdx,%r14,4), %xmm3, %xmm8
    vpcmpgtb %ymm1, %ymm6, %ymm3
    vpcmpgtb %ymm12, %ymm0, %ymm7
    vpcmpgtb %ymm7, %ymm11, %ymm1
    vpcmpgtb %ymm9, %ymm14, %ymm3
    vpcmpgtb %ymm3, %ymm0, %ymm15
    vpcmpgtb %ymm15, %ymm2, %ymm9
    vpcmpgtb %ymm1, %ymm14, %ymm12
    vpcmpgtb %ymm12, %ymm8, %ymm15
    vpcmpgtb (%rax), %ymm14, %ymm3
    vpcmpgtb 8(%rsp), %ymm3, %ymm8
    vpcmpgtb -200(%rbp), %ymm8, %ymm7
    vpcmpgtb (%r12), %ymm7, %ymm11
    vpcmpgtb 0x40(%r13), %ymm11, %ymm1
    vpcmpgtb (%rax,%r9,8), %ymm1, %ymm14
    vpcmpgtb 16(%r15,%rcx,2), %ymm14, %ymm3
    vpcmpgtb -4(%rdx,%r14,4), %ymm3, %ymm8
    vpcmpgtw %xmm7, %xmm2, %xmm1
    vpcmpgtw %xmm9, %xmm6, %xmm3
    vpcmpgtw %xmm3, %xmm8, %xmm7
    vpcmpgtw %xmm15, %xmm11, %xmm1
    vpcmpgtw %xmm1, %xmm6, %xmm12
    vpcmpgtw %xmm12, %xmm0, %xmm15
    vpcmpgtw %xmm7, %xmm11, %xmm9
    vpcmpgtw %xmm9, %xmm14, %xmm12
    vpcmpgtw (%rax), %xmm14, %xmm3
    vpcmpgtw 8(%rsp), %xmm3, %xmm8
    vpcmpgtw -200(%rbp), %xmm8, %xmm7
    vpcmpgtw (%r12), %xmm7, %xmm11
    vpcmpgtw 0x40(%r13), %xmm11, %xmm1
    vpcmpgtw (%rax,%r9,8), %xmm1, %xmm14
    vpcmpgtw 16(%r15,%rcx,2), %xmm14, %xmm3
    vpcmpgtw -4(%rdx,%r14,4), %xmm3, %xmm8
    vpcmpgtw %ymm3, %ymm0, %ymm7
    vpcmpgtw %ymm15, %ymm2, %ymm1
    vpcmpgtw %ymm1, %ymm14, %ymm3
    vpcmpgtw %ymm12, %ymm8, %ymm7
    vpcmpgtw %ymm7, %ymm2, %ymm9
    vpcmpgtw %ymm9, %ymm6, %ymm12
    vpcmpgtw %ymm3, %ymm8, %ymm15
    vpcmpgtw %ymm15, %ymm11, %ymm9
    vpcmpgtw (%rax), %ymm14, %ymm3
    vpcmpgtw 8(%rsp), %ymm3, %ymm8
    vpcmpgtw -200(%rbp), %ymm8, %ymm7
    vpcmpgtw (%r12), %ymm7, %ymm11
    vpcmpgtw 0x40(%r13), %ymm11, %ymm1
    vpcmpgtw (%rax,%r9,8), %ymm1, %ymm14
    vpcmpgtw 16(%r15,%rcx,2), %ymm14, %ymm3
    vpcmpgtw -4(%rdx,%r14,4), %ymm3, %ymm8
    vpcmpgtd %xmm1, %xmm6, %xmm3
    vpcmpgtd %xmm12, %xmm0, %xmm7
    vpcmpgtd %xmm7, %xmm11, %xmm1
    vpcmpgtd %xmm9, %xmm14, %xmm3
    vpcmpgtd %xmm3, %xmm0, %xmm15
    vpcmpgtd %xmm15, %xmm2, %xmm9
    vpcmpgtd %xmm1, %xmm14, %xmm12
    vpcmpgtd %xmm12, %xmm8, %xmm15
    vpcmpgtd (%rax), %xmm14, %xmm3
    vpcmpgtd 8(%rsp), %xmm3, %xmm8
    vpcmpgtd -200(%rbp), %xmm8, %xmm7
    vpcmpgtd (%r12), %xmm7, %xmm11
    vpcmpgtd 0x40(%r13), %xmm11, %xmm1
    vpcmpgtd (%rax,%r9,8), %xmm1, %xmm14
    vpcmpgtd 16(%r15,%rcx,2), %xmm14, %xmm3
    vpcmpgtd -4(%rdx,%r14,4), %xmm3, %xmm8
    vpcmpgtd %ymm7, %ymm2, %ymm1
    vpcmpgtd %ymm9, %ymm6, %ymm3
    vpcmpgtd %ymm3, %ymm8, %ymm7
    vpcmpgtd %ymm15, %ymm11, %ymm1
    vpcmpgtd %ymm1, %ymm6, %ymm12
    vpcmpgtd %ymm12, %ymm0, %ymm15
    vpcmpgtd %ymm7, %ymm11, %ymm9
    vpcmpgtd %ymm9, %ymm14, %ymm12
    vpcmpgtd (%rax), %ymm14, %ymm3
    vpcmpgtd 8(%rsp), %ymm3, %ymm8
    vpcmpgtd -200(%rbp), %ymm8, %ymm7
    vpcmpgtd (%r12), %ymm7, %ymm11
    vpcmpgtd 0x40(%r13), %ymm11, %ymm1
    vpcmpgtd (%rax,%r9,8), %ymm1, %ymm14
    vpcmpgtd 16(%r15,%rcx,2), %ymm14, %ymm3
    vpcmpgtd -4(%rdx,%r14,4), %ymm3, %ymm8
    vpandn %xmm3, %xmm0, %xmm7
    vpandn %xmm15, %xmm2, %xmm1
    vpandn %xmm1, %xmm14, %xmm3
    vpandn %xmm12, %xmm8, %xmm7
    vpandn %xmm7, %xmm2, %xmm9
    vpandn %xmm9, %xmm6, %xmm12
    vpandn %xmm3, %xmm8, %xmm15
    vpandn %xmm15, %xmm11, %xmm9
    vpandn (%rax), %xmm14, %xmm3
    vpandn 8(%rsp), %xmm3, %xmm8
    vpandn -200(%rbp), %xmm8, %xmm7
    vpandn (%r12), %xmm7, %xmm11
    vpandn 0x40(%r13), %xmm11, %xmm1
    vpandn (%rax,%r9,8), %xmm1, %xmm14
    vpandn 16(%r15,%rcx,2), %xmm14, %xmm3
    vpandn -4(%rdx,%r14,4), %xmm3, %xmm8
    vpandn %ymm1, %ymm6, %ymm3
    vpandn %ymm12, %ymm0, %ymm7
    vpandn %ymm7, %ymm11, %ymm1
    vpandn %ymm9, %ymm14, %ymm3
    vpandn %ymm3, %ymm0, %ymm15
    vpandn %ymm15, %ymm2, %ymm9
    vpandn %ymm1, %ymm14, %ymm12
    vpandn %ymm12, %ymm8, %ymm15
    vpandn (%rax), %ymm14, %ymm3
    vpandn 8(%rsp), %ymm3, %ymm8
    vpandn -200(%rbp), %ymm8, %ymm7
    vpandn (%r12), %ymm7, %ymm11
    vpandn 0x40(%r13), %ymm11, %ymm1
    vpandn (%rax,%r9,8), %ymm1, %ymm14
    vpandn 16(%r15,%rcx,2), %ymm14, %ymm3
    vpandn -4(%rdx,%r14,4), %ymm3, %ymm8
    vpunpcklbw %xmm7, %xmm2, %xmm1
    vpunpcklbw %xmm9, %xmm6, %xmm3
    vpunpcklbw %xmm3, %xmm8, %xmm7
    vpunpcklbw %xmm15, %xmm11, %xmm1
    vpunpcklbw %xmm1, %xmm6, %xmm12
    vpunpcklbw %xmm12, %xmm0, %xmm15
    vpunpcklbw %xmm7, %xmm11, %xmm9
    vpunpcklbw %xmm9, %xmm14, %xmm12
    vpunpcklbw (%rax), %xmm14, %xmm3
    vpunpcklbw 8(%rsp), %xmm3, %xmm8
    vpunpcklbw -200(%rbp), %xmm8, %xmm7
    vpunpcklbw (%r12), %xmm7, %xmm11
    vpunpcklbw 0x40(%r13), %xmm11, %xmm1
    vpunpcklbw (%rax,%r9,8), %xmm1, %xmm14
    vpunpcklbw 16(%r15,%rcx,2), %xmm14, %xmm3
    vpunpcklbw -4(%rdx,%r14,4), %xmm3, %xmm8
    vpunpcklbw %ymm3, %ymm0, %ymm7
    vpunpcklbw %ymm15, %ymm2, %ymm1
    vpunpcklbw %ymm1, %ymm14, %ymm3
    vpunpcklbw %ymm12, %ymm8, %ymm7
    vpunpcklbw %ymm7, %ymm2, %ymm9
    vpunpcklbw %ymm9, %ymm6, %ymm12
    vpunpcklbw %ymm3, %ymm8, %ymm15
    vpunpcklbw %ymm15, %ymm11, %ymm9
    vpunpcklbw (%rax), %ymm14, %ymm3
    vpunpcklbw 8(%rsp), %ymm3, %ymm8
    vpunpcklbw -200(%rbp), %ymm8, %ymm7
    vpunpcklbw (%r12), %ymm7, %ymm11
    vpunpcklbw 0x40(%r13), %ymm11, %ymm1
    vpunpcklbw (%rax,%r9,8), %ymm1, %ymm14
    vpunpcklbw 16(%r15,%rcx,2), %ymm14, %ymm3
    vpunpcklbw -4(%rdx,%r14,4), %ymm3, %ymm8
    vpunpcklwd %xmm1, %xmm6, %xmm3
    vpunpcklwd %xmm12, %xmm0, %xmm7
    vpunpcklwd %xmm7, %xmm11, %xmm1
    vpunpcklwd %xmm9, %xmm14, %xmm3
    vpunpcklwd %xmm3, %xmm0, %xmm15
    vpunpcklwd %xmm15, %xmm2, %xmm9
    vpunpcklwd %xmm1, %xmm14, %xmm12
    vpunpcklwd %xmm12, %xmm8, %xmm15
    vpunpcklwd (%rax), %xmm14, %xmm3
    vpunpcklwd 8(%rsp), %xmm3, %xmm8
    vpunpcklwd -200(%rbp), %xmm8, %xmm7
    vpunpcklwd (%r12), %xmm7, %xmm11
    vpunpcklwd 0x40(%r13), %xmm11, %xmm1
    vpunpcklwd (%rax,%r9,8), %xmm1, %xmm14
    vpunpcklwd 16(%r15,%rcx,2), %xmm14, %xmm3
    vpunpcklwd -4(%rdx,%r14,4), %xmm3, %xmm8
    vpunpcklwd %ymm7, %ymm2, %ymm1
    vpunpcklwd %ymm9, %ymm6, %ymm3
    vpunpcklwd %ymm3, %ymm8, %ymm7
    vpunpcklwd %ymm15, %ymm11, %ymm1
    vpunpcklwd %ymm1, %ymm6, %ymm12
    vpunpcklwd %ymm12, %ymm0, %ymm15
    vpunpcklwd %ymm7, %ymm11, %ymm9
    vpunpcklwd %ymm9, %ymm14, %ymm12
    vpunpcklwd (%rax), %ymm14, %ymm3
    vpunpcklwd 8(%rsp), %ymm3, %ymm8
    vpunpcklwd -200(%rbp), %ymm8, %ymm7
    vpunpcklwd (%r12), %ymm7, %ymm11
    vpunpcklwd 0x40(%r13), %ymm11, %ymm1
    vpunpcklwd (%rax,%r9,8), %ymm1, %ymm14
    vpunpcklwd 16(%r15,%rcx,2), %ymm14, %ymm3
    vpunpcklwd -4(%rdx,%r14,4), %ymm3, %ymm8
    vpunpckldq %xmm3, %xmm0, %xmm7
    vpunpckldq %xmm15, %xmm2, %xmm1
    vpunpckldq %xmm1, %xmm14, %xmm3
    vpunpckldq %xmm12, %xmm8, %xmm7
    vpunpckldq %xmm7, %xmm2, %xmm9
    vpunpckldq %xmm9, %xmm6, %xmm12
    vpunpckldq %xmm3, %xmm8, %xmm15
    vpunpckldq %xmm15, %xmm11, %xmm9
    vpunpckldq (%rax), %xmm14, %xmm3
    vpunpckldq 8(%rsp), %xmm3, %xmm8
    vpunpckldq -200(%rbp), %xmm8, %xmm7
    vpunpckldq (%r12), %xmm7, %xmm11
    vpunpckldq 0x40(%r13), %xmm11, %xmm1
    vpunpckldq (%rax,%r9,8), %xmm1, %xmm14
    vpunpckldq 16(%r15,%rcx,2), %xmm14, %xmm3
    vpunpckldq -4(%rdx,%r14,4), %xmm3, %xmm8
    vpunpckldq %ymm1, %ymm6, %ymm3
    vpunpckldq %ymm12, %ymm0, %ymm7
    vpunpckldq %ymm7, %ymm11, %ymm1
    vpunpckldq %ymm9, %ymm14, %ymm3
    vpunpckldq %ymm3, %ymm0, %ymm15
    vpunpckldq %ymm15, %ymm2, %ymm9
    vpunpckldq %ymm1, %ymm14, %ymm12
    vpunpckldq %ymm12, %ymm8, %ymm15
    vpunpckldq (%rax), %ymm14, %ymm3
    vpunpckldq 8(%rsp), %ymm3, %ymm8
    vpunpckldq -200(%rbp), %ymm8, %ymm7
    vpunpckldq (%r12), %ymm7, %ymm11
    vpunpckldq 0x40(%r13), %ymm11, %ymm1
    vpunpckldq (%rax,%r9,8), %ymm1, %ymm14
    vpunpckldq 16(%r15,%rcx,2), %ymm14, %ymm3
    vpunpckldq -4(%rdx,%r14,4), %ymm3, %ymm8
    vpunpcklqdq %xmm7, %xmm2, %xmm1
    vpunpcklqdq %xmm9, %xmm6, %xmm3
    vpunpcklqdq %xmm3, %xmm8, %xmm7
    vpunpcklqdq %xmm15, %xmm11, %xmm1
    vpunpcklqdq %xmm1, %xmm6, %xmm12
    vpunpcklqdq %xmm12, %xmm0, %xmm15
    vpunpcklqdq %xmm7, %xmm11, %xmm9
    vpunpcklqdq %xmm9, %xmm14, %xmm12
    vpunpcklqdq (%rax), %xmm14, %xmm3
    vpunpcklqdq 8(%rsp), %xmm3, %xmm8
    vpunpcklqdq -200(%rbp), %xmm8, %xmm7
    vpunpcklqdq (%r12), %xmm7, %xmm11
    vpunpcklqdq 0x40(%r13), %xmm11, %xmm1
    vpunpcklqdq (%rax,%r9,8), %xmm1, %xmm14
    vpunpcklqdq 16(%r15,%rcx,2), %xmm14, %xmm3
    vpunpcklqdq -4(%rdx,%r14,4), %xmm3, %xmm8
    vpunpcklqdq %ymm3, %ymm0, %ymm7
    vpunpcklqdq %ymm15, %ymm2, %ymm1
    vpunpcklqdq %ymm1, %ymm14, %ymm3
    vpunpcklqdq %ymm12, %ymm8, %ymm7
    vpunpcklqdq %ymm7, %ymm2, %ymm9
    vpunpcklqdq %ymm9, %ymm6, %ymm12
    vpunpcklqdq %ymm3, %ymm8, %ymm15
    vpunpcklqdq %ymm15, %ymm11, %ymm9
    vpunpcklqdq (%rax), %ymm14, %ymm3
    vpunpcklqdq 8(%rsp), %ymm3, %ymm8
    vpunpcklqdq -200(%rbp), %ymm8, %ymm7
    vpunpcklqdq (%r12), %ymm7, %ymm11
    vpunpcklqdq 0x40(%r13), %ymm11, %ymm1
    vpunpcklqdq (%rax,%r9,8), %ymm1, %ymm14
    vpunpcklqdq 16(%r15,%rcx,2), %ymm14, %ymm3
    vpunpcklqdq -4(%rdx,%r14,4), %ymm3, %ymm8
    vpunpckhbw %xmm1, %xmm6, %xmm3
    vpunpckhbw %xmm12, %xmm0, %xmm7
    vpunpckhbw %xmm7, %xmm11, %xmm1
    vpunpckhbw %xmm9, %xmm14, %xmm3
    vpunpckhbw %xmm3, %xmm0, %xmm15
    vpunpckhbw %xmm15, %xmm2, %xmm9
    vpunpckhbw %xmm1, %xmm14, %xmm12
    vpunpckhbw %xmm12, %xmm8, %xmm15
    vpunpckhbw (%rax), %xmm14, %xmm3
    vpunpckhbw 8(%rsp), %xmm3, %xmm8
    vpunpckhbw -200(%rbp), %xmm8, %xmm7
    vpunpckhbw (%r12), %xmm7, %xmm11
    vpunpckhbw 0x40(%r13), %xmm11, %xmm1
    vpunpckhbw (%rax,%r9,8), %xmm1, %xmm14
    vpunpckhbw 16(%r15,%rcx,2), %xmm14, %xmm3
    vpunpckhbw -4(%rdx,%r14,4), %xmm3, %xmm8
    vpunpckhbw %ymm7, %ymm2, %ymm1
    vpunpckhbw %ymm9, %ymm6, %ymm3
    vpunpckhbw %ymm3, %ymm8, %ymm7
    vpunpckhbw %ymm15, %ymm11, %ymm1
    vpunpckhbw %ymm1, %ymm6, %ymm12
    vpunpckhbw %ymm12, %ymm0, %ymm15
    vpunpckhbw %ymm7, %ymm11, %ymm9
    vpunpckhbw %ymm9, %ymm14, %ymm12
    vpunpckhbw (%rax), %ymm14, %ymm3
    vpunpckhbw 8(%rsp), %ymm3, %ymm8
    vpunpckhbw -200(%rbp), %ymm8, %ymm7
    vpunpckhbw (%r12), %ymm7, %ymm11
    vpunpckhbw 0x40(%r13), %ymm11, %ymm1
    vpunpckhbw (%rax,%r9,8), %ymm1, %ymm14
    vpunpckhbw 16(%r15,%rcx,2), %ymm14, %ymm3
    vpunpckhbw -4(%rdx,%r14,4), %ymm3, %ymm8
    vpunpckhwd %xmm3, %xmm0, %xmm7
    vpunpckhwd %xmm15, %xmm2, %xmm1
    vpunpckhwd %xmm1, %xmm14, %xmm3
    vpunpckhwd %xmm12, %xmm8, %xmm7
    vpunpckhwd %xmm7, %xmm2, %xmm9
    vpunpckhwd %xmm9, %xmm6, %xmm12
    vpunpckhwd %xmm3, %xmm8, %xmm15
    vpunpckhwd %xmm15, %xmm11, %xmm9
    vpunpckhwd (%rax), %xmm14, %xmm3
    vpunpckhwd 8(%rsp), %xmm3, %xmm8
    vpunpckhwd -200(%rbp), %xmm8, %xmm7
    vpunpckhwd (%r12), %xmm7, %xmm11
    vpunpckhwd 0x40(%r13), %xmm11, %xmm1
    vpunpckhwd (%rax,%r9,8), %xmm1, %xmm14
    vpunpckhwd 16(%r15,%rcx,2), %xmm14, %xmm3
    vpunpckhwd -4(%rdx,%r14,4), %xmm3, %xmm8
    vpunpckhwd %ymm1, %ymm6, %ymm3
    vpunpckhwd %ymm12, %ymm0, %ymm7
    vpunpckhwd %ymm7, %ymm11, %ymm1
    vpunpckhwd %ymm9, %ymm14, %ymm3
    vpunpckhwd %ymm3, %ymm0, %ymm15
    vpunpckhwd %ymm15, %ymm2, %ymm9
    vpunpckhwd %ymm1, %ymm14, %ymm12
    vpunpckhwd %ymm12, %ymm8, %ymm15
    vpunpckhwd (%rax), %ymm14, %ymm3
    vpunpckhwd 8(%rsp), %ymm3, %ymm8
    vpunpckhwd -200(%rbp), %ymm8, %ymm7
    vpunpckhwd (%r12), %ymm7, %ymm11
    vpunpckhwd 0x40(%r13), %ymm11, %ymm1
    vpunpckhwd (%rax,%r9,8), %ymm1, %ymm14
    vpunpckhwd 16(%r15,%rcx,2), %ymm14, %ymm3
    vpunpckhwd -4(%rdx,%r14,4), %ymm3, %ymm8
    vpunpckhdq %xmm7, %xmm2, %xmm1
    vpunpckhdq %xmm9, %xmm6, %xmm3
    vpunpckhdq %xmm3, %xmm8, %xmm7
    vpunpckhdq %xmm15, %xmm11, %xmm1
    vpunpckhdq %xmm1, %xmm6, %xmm12
    vpunpckhdq %xmm12, %xmm0, %xmm15
    vpunpckhdq %xmm7, %xmm11, %xmm9
    vpunpckhdq %xmm9, %xmm14, %xmm12
    vpunpckhdq (%rax), %xmm14, %xmm3
    vpunpckhdq 8(%rsp), %xmm3, %xmm8
    vpunpckhdq -200(%rbp), %xmm8, %xmm7
    vpunpckhdq (%r12), %xmm7, %xmm11
    vpunpckhdq 0x40(%r13), %xmm11, %xmm1
    vpunpckhdq (%rax,%r9,8), %xmm1, %xmm14
    vpunpckhdq 16(%r15,%rcx,2), %xmm14, %xmm3
    vpunpckhdq -4(%rdx,%r14,4), %xmm3, %xmm8
    vpunpckhdq %ymm3, %ymm0, %ymm7
    vpunpckhdq %ymm15, %ymm2, %ymm1
    vpunpckhdq %ymm1, %ymm14, %ymm3
    vpunpckhdq %ymm12, %ymm8, %ymm7
    vpunpckhdq %ymm7, %ymm2, %ymm9
    vpunpckhdq %ymm9, %ymm6, %ymm12
    vpunpckhdq %ymm3, %ymm8, %ymm15
    vpunpckhdq %ymm15, %ymm11, %ymm9
    vpunpckhdq (%rax), %ymm14, %ymm3
    vpunpckhdq 8(%rsp), %ymm3, %ymm8
    vpunpckhdq -200(%rbp), %ymm8, %ymm7
    vpunpckhdq (%r12), %ymm7, %ymm11
    vpunpckhdq 0x40(%r13), %ymm11, %ymm1
    vpunpckhdq (%rax,%r9,8), %ymm1, %ymm14
    vpunpckhdq 16(%r15,%rcx,2), %ymm14, %ymm3
    vpunpckhdq -4(%rdx,%r14,4), %ymm3, %ymm8
    vpunpckhqdq %xmm1, %xmm6, %xmm3
    vpunpckhqdq %xmm12, %xmm0, %xmm7
    vpunpckhqdq %xmm7, %xmm11, %xmm1
    vpunpckhqdq %xmm9, %xmm14, %xmm3
    vpunpckhqdq %xmm3, %xmm0, %xmm15
    vpunpckhqdq %xmm15, %xmm2, %xmm9
    vpunpckhqdq %xmm1, %xmm14, %xmm12
    vpunpckhqdq %xmm12, %xmm8, %xmm15
    vpunpckhqdq (%rax), %xmm14, %xmm3
    vpunpckhqdq 8(%rsp), %xmm3, %xmm8
    vpunpckhqdq -200(%rbp), %xmm8, %xmm7
    vpunpckhqdq (%r12), %xmm7, %xmm11
    vpunpckhqdq 0x40(%r13), %xmm11, %xmm1
    vpunpckhqdq (%rax,%r9,8), %xmm1, %xmm14
    vpunpckhqdq 16(%r15,%rcx,2), %xmm14, %xmm3
    vpunpckhqdq -4(%rdx,%r14,4), %xmm3, %xmm8
    vpunpckhqdq %ymm7, %ymm2, %ymm1
    vpunpckhqdq %ymm9, %ymm6, %ymm3
    vpunpckhqdq %ymm3, %ymm8, %ymm7
    vpunpckhqdq %ymm15, %ymm11, %ymm1
    vpunpckhqdq %ymm1, %ymm6, %ymm12
    vpunpckhqdq %ymm12, %ymm0, %ymm15
    vpunpckhqdq %ymm7, %ymm11, %ymm9
    vpunpckhqdq %ymm9, %ymm14, %ymm12
    vpunpckhqdq (%rax), %ymm14, %ymm3
    vpunpckhqdq 8(%rsp), %ymm3, %ymm8
    vpunpckhqdq -200(%rbp), %ymm8, %ymm7
    vpunpckhqdq (%r12), %ymm7, %ymm11
    vpunpckhqdq 0x40(%r13), %ymm11, %ymm1
    vpunpckhqdq (%rax,%r9,8), %ymm1, %ymm14
    vpunpckhqdq 16(%r15,%rcx,2), %ymm14, %ymm3
    vpunpckhqdq -4(%rdx,%r14,4), %ymm3, %ymm8
    vpacksswb %xmm3, %xmm0, %xmm7
    vpacksswb %xmm15, %xmm2, %xmm1
    vpacksswb %xmm1, %xmm14, %xmm3
    vpacksswb %xmm12, %xmm8, %xmm7
    vpacksswb %xmm7, %xmm2, %xmm9
    vpacksswb %xmm9, %xmm6, %xmm12
    vpacksswb %xmm3, %xmm8, %xmm15
    vpacksswb %xmm15, %xmm11, %xmm9
    vpacksswb (%rax), %xmm14, %xmm3
    vpacksswb 8(%rsp), %xmm3, %xmm8
    vpacksswb -200(%rbp), %xmm8, %xmm7
    vpacksswb (%r12), %xmm7, %xmm11
    vpacksswb 0x40(%r13), %xmm11, %xmm1
    vpacksswb (%rax,%r9,8), %xmm1, %xmm14
    vpacksswb 16(%r15,%rcx,2), %xmm14, %xmm3
    vpacksswb -4(%rdx,%r14,4), %xmm3, %xmm8
    vpacksswb %ymm1, %ymm6, %ymm3
    vpacksswb %ymm12, %ymm0, %ymm7
    vpacksswb %ymm7, %ymm11, %ymm1
    vpacksswb %ymm9, %ymm14, %ymm3
    vpacksswb %ymm3, %ymm0, %ymm15
    vpacksswb %ymm15, %ymm2, %ymm9
    vpacksswb %ymm1, %ymm14, %ymm12
    vpacksswb %ymm12, %ymm8, %ymm15
    vpacksswb (%rax), %ymm14, %ymm3
    vpacksswb 8(%rsp), %ymm3, %ymm8
    vpacksswb -200(%rbp), %ymm8, %ymm7
    vpacksswb (%r12), %ymm7, %ymm11
    vpacksswb 0x40(%r13), %ymm11, %ymm1
    vpacksswb (%rax,%r9,8), %ymm1, %ymm14
    vpacksswb 16(%r15,%rcx,2), %ymm14, %ymm3
    vpacksswb -4(%rdx,%r14,4), %ymm3, %ymm8
    vpackssdw %xmm7, %xmm2, %xmm1
    vpackssdw %xmm9, %xmm6, %xmm3
    vpackssdw %xmm3, %xmm8, %xmm7
    vpackssdw %xmm15, %xmm11, %xmm1
    vpackssdw %xmm1, %xmm6, %xmm12
    vpackssdw %xmm12, %xmm0, %xmm15
    vpackssdw %xmm7, %xmm11, %xmm9
    vpackssdw %xmm9, %xmm14, %xmm12
    vpackssdw (%rax), %xmm14, %xmm3
    vpackssdw 8(%rsp), %xmm3, %xmm8
    vpackssdw -200(%rbp), %xmm8, %xmm7
    vpackssdw (%r12), %xmm7, %xmm11
    vpackssdw 0x40(%r13), %xmm11, %xmm1
    vpackssdw (%rax,%r9,8), %xmm1, %xmm14
    vpackssdw 16(%r15,%rcx,2), %xmm14, %xmm3
    vpackssdw -4(%rdx,%r14,4), %xmm3, %xmm8
    vpackssdw %ymm3, %ymm0, %ymm7
    vpackssdw %ymm15, %ymm2, %ymm1
    vpackssdw %ymm1, %ymm14, %ymm3
    vpackssdw %ymm12, %ymm8, %ymm7
    vpackssdw %ymm7, %ymm2, %ymm9
    vpackssdw %ymm9, %ymm6, %ymm12
    vpackssdw %ymm3, %ymm8, %ymm15
    vpackssdw %ymm15, %ymm11, %ymm9
    vpackssdw (%rax), %ymm14, %ymm3
    vpackssdw 8(%rsp), %ymm3, %ymm8
    vpackssdw -200(%rbp), %ymm8, %ymm7
    vpackssdw (%r12), %ymm7, %ymm11
    vpackssdw 0x40(%r13), %ymm11, %ymm1
    vpackssdw (%rax,%r9,8), %ymm1, %ymm14
    vpackssdw 16(%r15,%rcx,2), %ymm14, %ymm3
    vpackssdw -4(%rdx,%r14,4), %ymm3, %ymm8
    vpackuswb %xmm1, %xmm6, %xmm3
    vpackuswb %xmm12, %xmm0, %xmm7
    vpackuswb %xmm7, %xmm11, %xmm1
    vpackuswb %xmm9, %xmm14, %xmm3
    vpackuswb %xmm3, %xmm0, %xmm15
    vpackuswb %xmm15, %xmm2, %xmm9
    vpackuswb %xmm1, %xmm14, %xmm12
    vpackuswb %xmm12, %xmm8, %xmm15
    vpackuswb (%rax), %xmm14, %xmm3
    vpackuswb 8(%rsp), %xmm3, %xmm8
    vpackuswb -200(%rbp), %xmm8, %xmm7
    vpackuswb (%r12), %xmm7, %xmm11
    vpackuswb 0x40(%r13), %xmm11, %xmm1
    vpackuswb (%rax,%r9,8), %xmm1, %xmm14
    vpackuswb 16(%r15,%rcx,2), %xmm14, %xmm3
    vpackuswb -4(%rdx,%r14,4), %xmm3, %xmm8
    vpackuswb %ymm7, %ymm2, %ymm1
    vpackuswb %ymm9, %ymm6, %ymm3
    vpackuswb %ymm3, %ymm8, %ymm7
    vpackuswb %ymm15, %ymm11, %ymm1
    vpackuswb %ymm1, %ymm6, %ymm12
    vpackuswb %ymm12, %ymm0, %ymm15
    vpackuswb %ymm7, %ymm11, %ymm9
    vpackuswb %ymm9, %ymm14, %ymm12
    vpackuswb (%rax), %ymm14, %ymm3
    vpackuswb 8(%rsp), %ymm3, %ymm8
    vpackuswb -200(%rbp), %ymm8, %ymm7
    vpackuswb (%r12), %ymm7, %ymm11
    vpackuswb 0x40(%r13), %ymm11, %ymm1
    vpackuswb (%rax,%r9,8), %ymm1, %ymm14
    vpackuswb 16(%r15,%rcx,2), %ymm14, %ymm3
    vpackuswb -4(%rdx,%r14,4), %ymm3, %ymm8
    vsubpd %xmm3, %xmm0, %xmm7
    vsubpd %xmm15, %xmm2, %xmm1
    vsubpd %xmm1, %xmm14, %xmm3
    vsubpd %xmm12, %xmm8, %xmm7
    vsubpd %xmm7, %xmm2, %xmm9
    vsubpd %xmm9, %xmm6, %xmm12
    vsubpd %xmm3, %xmm8, %xmm15
    vsubpd %xmm15, %xmm11, %xmm9
    vsubpd (%rax), %xmm14, %xmm3
    vsubpd 8(%rsp), %xmm3, %xmm8
    vsubpd -200(%rbp), %xmm8, %xmm7
    vsubpd (%r12), %xmm7, %xmm11
    vsubpd 0x40(%r13), %xmm11, %xmm1
    vsubpd (%rax,%r9,8), %xmm1, %xmm14
    vsubpd 16(%r15,%rcx,2), %xmm14, %xmm3
    vsubpd -4(%rdx,%r14,4), %xmm3, %xmm8
    vsubpd %ymm1, %ymm6, %ymm3
    vsubpd %ymm12, %ymm0, %ymm7
    vsubpd %ymm7, %ymm11, %ymm1
    vsubpd %ymm9, %ymm14, %ymm3
    vsubpd %ymm3, %ymm0, %ymm15
    vsubpd %ymm15, %ymm2, %ymm9
    vsubpd %ymm1, %ymm14, %ymm12
    vsubpd %ymm12, %ymm8, %ymm15
    vsubpd (%rax), %ymm14, %ymm3
    vsubpd 8(%rsp), %ymm3, %ymm8
    vsubpd -200(%rbp), %ymm8, %ymm7
    vsubpd (%r12), %ymm7, %ymm11
    vsubpd 0x40(%r13), %ymm11, %ymm1
    vsubpd (%rax,%r9,8), %ymm1, %ymm14
    vsubpd 16(%r15,%rcx,2), %ymm14, %ymm3
    vsubpd -4(%rdx,%r14,4), %ymm3, %ymm8
    vdivpd %xmm7, %xmm2, %xmm1
    vdivpd %xmm9, %xmm6, %xmm3
    vdivpd %xmm3, %xmm8, %xmm7
    vdivpd %xmm15, %xmm11, %xmm1
    vdivpd %xmm1, %xmm6, %xmm12
    vdivpd %xmm12, %xmm0, %xmm15
    vdivpd %xmm7, %xmm11, %xmm9
    vdivpd %xmm9, %xmm14, %xmm12
    vdivpd (%rax), %xmm14, %xmm3
    vdivpd 8(%rsp), %xmm3, %xmm8
    vdivpd -200(%rbp), %xmm8, %xmm7
    vdivpd (%r12), %xmm7, %xmm11
    vdivpd 0x40(%r13), %xmm11, %xmm1
    vdivpd (%rax,%r9,8), %xmm1, %xmm14
    vdivpd 16(%r15,%rcx,2), %xmm14, %xmm3
    vdivpd -4(%rdx,%r14,4), %xmm3, %xmm8
    vdivpd %ymm3, %ymm0, %ymm7
    vdivpd %ymm15, %ymm2, %ymm1
    vdivpd %ymm1, %ymm14, %ymm3
    vdivpd %ymm12, %ymm8, %ymm7
    vdivpd %ymm7, %ymm2, %ymm9
    vdivpd %ymm9, %ymm6, %ymm12
    vdivpd %ymm3, %ymm8, %ymm15
    vdivpd %ymm15, %ymm11, %ymm9
    vdivpd (%rax), %ymm14, %ymm3
    vdivpd 8(%rsp), %ymm3, %ymm8
    vdivpd -200(%rbp), %ymm8, %ymm7
    vdivpd (%r12), %ymm7, %ymm11
    vdivpd 0x40(%r13), %ymm11, %ymm1
    vdivpd (%rax,%r9,8), %ymm1, %ymm14
    vdivpd 16(%r15,%rcx,2), %ymm14, %ymm3
    vdivpd -4(%rdx,%r14,4), %ymm3, %ymm8
    vminpd %xmm1, %xmm6, %xmm3
    vminpd %xmm12, %xmm0, %xmm7
    vminpd %xmm7, %xmm11, %xmm1
    vminpd %xmm9, %xmm14, %xmm3
    vminpd %xmm3, %xmm0, %xmm15
    vminpd %xmm15, %xmm2, %xmm9
    vminpd %xmm1, %xmm14, %xmm12
    vminpd %xmm12, %xmm8, %xmm15
    vminpd (%rax), %xmm14, %xmm3
    vminpd 8(%rsp), %xmm3, %xmm8
    vminpd -200(%rbp), %xmm8, %xmm7
    vminpd (%r12), %xmm7, %xmm11
    vminpd 0x40(%r13), %xmm11, %xmm1
    vminpd (%rax,%r9,8), %xmm1, %xmm14
    vminpd 16(%r15,%rcx,2), %xmm14, %xmm3
    vminpd -4(%rdx,%r14,4), %xmm3, %xmm8
    vminpd %ymm7, %ymm2, %ymm1
    vminpd %ymm9, %ymm6, %ymm3
    vminpd %ymm3, %ymm8, %ymm7
    vminpd %ymm15, %ymm11, %ymm1
    vminpd %ymm1, %ymm6, %ymm12
    vminpd %ymm12, %ymm0, %ymm15
    vminpd %ymm7, %ymm11, %ymm9
    vminpd %ymm9, %ymm14, %ymm12
    vminpd (%rax), %ymm14, %ymm3
    vminpd 8(%rsp), %ymm3, %ymm8
    vminpd -200(%rbp), %ymm8, %ymm7
    vminpd (%r12), %ymm7, %ymm11
    vminpd 0x40(%r13), %ymm11, %ymm1
    vminpd (%rax,%r9,8), %ymm1, %ymm14
    vminpd 16(%r15,%rcx,2), %ymm14, %ymm3
    vminpd -4(%rdx,%r14,4), %ymm3, %ymm8
    vmaxpd %xmm3, %xmm0, %xmm7
    vmaxpd %xmm15, %xmm2, %xmm1
    vmaxpd %xmm1, %xmm14, %xmm3
    vmaxpd %xmm12, %xmm8, %xmm7
    vmaxpd %xmm7, %xmm2, %xmm9
    vmaxpd %xmm9, %xmm6, %xmm12
    vmaxpd %xmm3, %xmm8, %xmm15
    vmaxpd %xmm15, %xmm11, %xmm9
    vmaxpd (%rax), %xmm14, %xmm3
    vmaxpd 8(%rsp), %xmm3, %xmm8
    vmaxpd -200(%rbp), %xmm8, %xmm7
    vmaxpd (%r12), %xmm7, %xmm11
    vmaxpd 0x40(%r13), %xmm11, %xmm1
    vmaxpd (%rax,%r9,8), %xmm1, %xmm14
    vmaxpd 16(%r15,%rcx,2), %xmm14, %xmm3
    vmaxpd -4(%rdx,%r14,4), %xmm3, %xmm8
    vmaxpd %ymm1, %ymm6, %ymm3
    vmaxpd %ymm12, %ymm0, %ymm7
    vmaxpd %ymm7, %ymm11, %ymm1
    vmaxpd %ymm9, %ymm14, %ymm3
    vmaxpd %ymm3, %ymm0, %ymm15
    vmaxpd %ymm15, %ymm2, %ymm9
    vmaxpd %ymm1, %ymm14, %ymm12
    vmaxpd %ymm12, %ymm8, %ymm15
    vmaxpd (%rax), %ymm14, %ymm3
    vmaxpd 8(%rsp), %ymm3, %ymm8
    vmaxpd -200(%rbp), %ymm8, %ymm7
    vmaxpd (%r12), %ymm7, %ymm11
    vmaxpd 0x40(%r13), %ymm11, %ymm1
    vmaxpd (%rax,%r9,8), %ymm1, %ymm14
    vmaxpd 16(%r15,%rcx,2), %ymm14, %ymm3
    vmaxpd -4(%rdx,%r14,4), %ymm3, %ymm8
    vandnpd %xmm7, %xmm2, %xmm1
    vandnpd %xmm9, %xmm6, %xmm3
    vandnpd %xmm3, %xmm8, %xmm7
    vandnpd %xmm15, %xmm11, %xmm1
    vandnpd %xmm1, %xmm6, %xmm12
    vandnpd %xmm12, %xmm0, %xmm15
    vandnpd %xmm7, %xmm11, %xmm9
    vandnpd %xmm9, %xmm14, %xmm12
    vandnpd (%rax), %xmm14, %xmm3
    vandnpd 8(%rsp), %xmm3, %xmm8
    vandnpd -200(%rbp), %xmm8, %xmm7
    vandnpd (%r12), %xmm7, %xmm11
    vandnpd 0x40(%r13), %xmm11, %xmm1
    vandnpd (%rax,%r9,8), %xmm1, %xmm14
    vandnpd 16(%r15,%rcx,2), %xmm14, %xmm3
    vandnpd -4(%rdx,%r14,4), %xmm3, %xmm8
    vandnpd %ymm3, %ymm0, %ymm7
    vandnpd %ymm15, %ymm2, %ymm1
    vandnpd %ymm1, %ymm14, %ymm3
    vandnpd %ymm12, %ymm8, %ymm7
    vandnpd %ymm7, %ymm2, %ymm9
    vandnpd %ymm9, %ymm6, %ymm12
    vandnpd %ymm3, %ymm8, %ymm15
    vandnpd %ymm15, %ymm11, %ymm9
    vandnpd (%rax), %ymm14, %ymm3
    vandnpd 8(%rsp), %ymm3, %ymm8
    vandnpd -200(%rbp), %ymm8, %ymm7
    vandnpd (%r12), %ymm7, %ymm11
    vandnpd 0x40(%r13), %ymm11, %ymm1
    vandnpd (%rax,%r9,8), %ymm1, %ymm14
    vandnpd 16(%r15,%rcx,2), %ymm14, %ymm3
    vandnpd -4(%rdx,%r14,4), %ymm3, %ymm8
    vsubps %xmm1, %xmm6, %xmm3
    vsubps %xmm12, %xmm0, %xmm7
    vsubps %xmm7, %xmm11, %xmm1
    vsubps %xmm9, %xmm14, %xmm3
    vsubps %xmm3, %xmm0, %xmm15
    vsubps %xmm15, %xmm2, %xmm9
    vsubps %xmm1, %xmm14, %xmm12
    vsubps %xmm12, %xmm8, %xmm15
    vsubps (%rax), %xmm14, %xmm3
    vsubps 8(%rsp), %xmm3, %xmm8
    vsubps -200(%rbp), %xmm8, %xmm7
    vsubps (%r12), %xmm7, %xmm11
    vsubps 0x40(%r13), %xmm11, %xmm1
    vsubps (%rax,%r9,8), %xmm1, %xmm14
    vsubps 16(%r15,%rcx,2), %xmm14, %xmm3
    vsubps -4(%rdx,%r14,4), %xmm3, %xmm8
    vsubps %ymm7, %ymm2, %ymm1
    vsubps %ymm9, %ymm6, %ymm3
    vsubps %ymm3, %ymm8, %ymm7
    vsubps %ymm15, %ymm11, %ymm1
    vsubps %ymm1, %ymm6, %ymm12
    vsubps %ymm12, %ymm0, %ymm15
    vsubps %ymm7, %ymm11, %ymm9
    vsubps %ymm9, %ymm14, %ymm12
    vsubps (%rax), %ymm14, %ymm3
    vsubps 8(%rsp), %ymm3, %ymm8
    vsubps -200(%rbp), %ymm8, %ymm7
    vsubps (%r12), %ymm7, %ymm11
    vsubps 0x40(%r13), %ymm11, %ymm1
    vsubps (%rax,%r9,8), %ymm1, %ymm14
    vsubps 16(%r15,%rcx,2), %ymm14, %ymm3
    vsubps -4(%rdx,%r14,4), %ymm3, %ymm8
    vdivps %xmm3, %xmm0, %xmm7
    vdivps %xmm15, %xmm2, %xmm1
    vdivps %xmm1, %xmm14, %xmm3
    vdivps %xmm12, %xmm8, %xmm7
    vdivps %xmm7, %xmm2, %xmm9
    vdivps %xmm9, %xmm6, %xmm12
    vdivps %xmm3, %xmm8, %xmm15
    vdivps %xmm15, %xmm11, %xmm9
    vdivps (%rax), %xmm14, %xmm3
    vdivps 8(%rsp), %xmm3, %xmm8
    vdivps -200(%rbp), %xmm8, %xmm7
    vdivps (%r12), %xmm7, %xmm11
    vdivps 0x40(%r13), %xmm11, %xmm1
    vdivps (%rax,%r9,8), %xmm1, %xmm14
    vdivps 16(%r15,%rcx,2), %xmm14, %xmm3
    vdivps -4(%rdx,%r14,4), %xmm3, %xmm8
    vdivps %ymm1, %ymm6, %ymm3
    vdivps %ymm12, %ymm0, %ymm7
    vdivps %ymm7, %ymm11, %ymm1
    vdivps %ymm9, %ymm14, %ymm3
    vdivps %ymm3, %ymm0, %ymm15
    vdivps %ymm15, %ymm2, %ymm9
    vdivps %ymm1, %ymm14, %ymm12
    vdivps %ymm12, %ymm8, %ymm15
    vdivps (%rax), %ymm14, %ymm3
    vdivps 8(%rsp), %ymm3, %ymm8
    vdivps -200(%rbp), %ymm8, %ymm7
    vdivps (%r12), %ymm7, %ymm11
    vdivps 0x40(%r13), %ymm11, %ymm1
    vdivps (%rax,%r9,8), %ymm1, %ymm14
    vdivps 16(%r15,%rcx,2), %ymm14, %ymm3
    vdivps -4(%rdx,%r14,4), %ymm3, %ymm8
    vminps %xmm7, %xmm2, %xmm1
    vminps %xmm9, %xmm6, %xmm3
    vminps %xmm3, %xmm8, %xmm7
    vminps %xmm15, %xmm11, %xmm1
    vminps %xmm1, %xmm6, %xmm12
    vminps %xmm12, %xmm0, %xmm15
    vminps %xmm7, %xmm11, %xmm9
    vminps %xmm9, %xmm14, %xmm12
    vminps (%rax), %xmm14, %xmm3
    vminps 8(%rsp), %xmm3, %xmm8
    vminps -200(%rbp), %xmm8, %xmm7
    vminps (%r12), %xmm7, %xmm11
    vminps 0x40(%r13), %xmm11, %xmm1
    vminps (%rax,%r9,8), %xmm1, %xmm14
    vminps 16(%r15,%rcx,2), %xmm14, %xmm3
    vminps -4(%rdx,%r14,4), %xmm3, %xmm8
    vminps %ymm3, %ymm0, %ymm7
    vminps %ymm15, %ymm2, %ymm1
    vminps %ymm1, %ymm14, %ymm3
    vminps %ymm12, %ymm8, %ymm7
    vminps %ymm7, %ymm2, %ymm9
    vminps %ymm9, %ymm6, %ymm12
    vminps %ymm3, %ymm8, %ymm15
    vminps %ymm15, %ymm11, %ymm9
    vminps (%rax), %ymm14, %ymm3
    vminps 8(%rsp), %ymm3, %ymm8
    vminps -200(%rbp), %ymm8, %ymm7
    vminps (%r12), %ymm7, %ymm11
    vminps 0x40(%r13), %ymm11, %ymm1
    vminps (%rax,%r9,8), %ymm1, %ymm14
    vminps 16(%r15,%rcx,2), %ymm14, %ymm3
    vminps -4(%rdx,%r14,4), %ymm3, %ymm8
    vmaxps %xmm1, %xmm6, %xmm3
    vmaxps %xmm12, %xmm0, %xmm7
    vmaxps %xmm7, %xmm11, %xmm1
    vmaxps %xmm9, %xmm14, %xmm3
    vmaxps %xmm3, %xmm0, %xmm15
    vmaxps %xmm15, %xmm2, %xmm9
    vmaxps %xmm1, %xmm14, %xmm12
    vmaxps %xmm12, %xmm8, %xmm15
    vmaxps (%rax), %xmm14, %xmm3
    vmaxps 8(%rsp), %xmm3, %xmm8
    vmaxps -200(%rbp), %xmm8, %xmm7
    vmaxps (%r12), %xmm7, %xmm11
    vmaxps 0x40(%r13), %xmm11, %xmm1
    vmaxps (%rax,%r9,8), %xmm1, %xmm14
    vmaxps 16(%r15,%rcx,2), %xmm14, %xmm3
    vmaxps -4(%rdx,%r14,4), %xmm3, %xmm8
    vmaxps %ymm7, %ymm2, %ymm1
    vmaxps %ymm9, %ymm6, %ymm3
    vmaxps %ymm3, %ymm8, %ymm7
    vmaxps %ymm15, %ymm11, %ymm1
    vmaxps %ymm1, %ymm6, %ymm12
    vmaxps %ymm12, %ymm0, %ymm15
    vmaxps %ymm7, %ymm11, %ymm9
    vmaxps %ymm9, %ymm14, %ymm12
    vmaxps (%rax), %ymm14, %ymm3
    vmaxps 8(%rsp), %ymm3, %ymm8
    vmaxps -200(%rbp), %ymm8, %ymm7
    vmaxps (%r12), %ymm7, %ymm11
    vmaxps 0x40(%r13), %ymm11, %ymm1
    vmaxps (%rax,%r9,8), %ymm1, %ymm14
    vmaxps 16(%r15,%rcx,2), %ymm14, %ymm3
    vmaxps -4(%rdx,%r14,4), %ymm3, %ymm8
    vandnps %xmm3, %xmm0, %xmm7
    vandnps %xmm15, %xmm2, %xmm1
    vandnps %xmm1, %xmm14, %xmm3
    vandnps %xmm12, %xmm8, %xmm7
    vandnps %xmm7, %xmm2, %xmm9
    vandnps %xmm9, %xmm6, %xmm12
    vandnps %xmm3, %xmm8, %xmm15
    vandnps %xmm15, %xmm11, %xmm9
    vandnps (%rax), %xmm14, %xmm3
    vandnps 8(%rsp), %xmm3, %xmm8
    vandnps -200(%rbp), %xmm8, %xmm7
    vandnps (%r12), %xmm7, %xmm11
    vandnps 0x40(%r13), %xmm11, %xmm1
    vandnps (%rax,%r9,8), %xmm1, %xmm14
    vandnps 16(%r15,%rcx,2), %xmm14, %xmm3
    vandnps -4(%rdx,%r14,4), %xmm3, %xmm8
    vandnps %ymm1, %ymm6, %ymm3
    vandnps %ymm12, %ymm0, %ymm7
    vandnps %ymm7, %ymm11, %ymm1
    vandnps %ymm9, %ymm14, %ymm3
    vandnps %ymm3, %ymm0, %ymm15
    vandnps %ymm15, %ymm2, %ymm9
    vandnps %ymm1, %ymm14, %ymm12
    vandnps %ymm12, %ymm8, %ymm15
    vandnps (%rax), %ymm14, %ymm3
    vandnps 8(%rsp), %ymm3, %ymm8
    vandnps -200(%rbp), %ymm8, %ymm7
    vandnps (%r12), %ymm7, %ymm11
    vandnps 0x40(%r13), %ymm11, %ymm1
    vandnps (%rax,%r9,8), %ymm1, %ymm14
    vandnps 16(%r15,%rcx,2), %ymm14, %ymm3
    vandnps -4(%rdx,%r14,4), %ymm3, %ymm8
    vpshufb %xmm7, %xmm2, %xmm1
    vpshufb %xmm9, %xmm6, %xmm3
    vpshufb %xmm3, %xmm8, %xmm7
    vpshufb %xmm15, %xmm11, %xmm1
    vpshufb %xmm1, %xmm6, %xmm12
    vpshufb %xmm12, %xmm0, %xmm15
    vpshufb %xmm7, %xmm11, %xmm9
    vpshufb %xmm9, %xmm14, %xmm12
    vpshufb (%rax), %xmm14, %xmm3
    vpshufb 8(%rsp), %xmm3, %xmm8
    vpshufb -200(%rbp), %xmm8, %xmm7
    vpshufb (%r12), %xmm7, %xmm11
    vpshufb 0x40(%r13), %xmm11, %xmm1
    vpshufb (%rax,%r9,8), %xmm1, %xmm14
    vpshufb 16(%r15,%rcx,2), %xmm14, %xmm3
    vpshufb -4(%rdx,%r14,4), %xmm3, %xmm8
    vpshufb %ymm3, %ymm0, %ymm7
    vpshufb %ymm15, %ymm2, %ymm1
    vpshufb %ymm1, %ymm14, %ymm3
    vpshufb %ymm12, %ymm8, %ymm7
    vpshufb %ymm7, %ymm2, %ymm9
    vpshufb %ymm9, %ymm6, %ymm12
    vpshufb %ymm3, %ymm8, %ymm15
    vpshufb %ymm15, %ymm11, %ymm9
    vpshufb (%rax), %ymm14, %ymm3
    vpshufb 8(%rsp), %ymm3, %ymm8
    vpshufb -200(%rbp), %ymm8, %ymm7
    vpshufb (%r12), %ymm7, %ymm11
    vpshufb 0x40(%r13), %ymm11, %ymm1
    vpshufb (%rax,%r9,8), %ymm1, %ymm14
    vpshufb 16(%r15,%rcx,2), %ymm14, %ymm3
    vpshufb -4(%rdx,%r14,4), %ymm3, %ymm8
    vphaddw %xmm1, %xmm6, %xmm3
    vphaddw %xmm12, %xmm0, %xmm7
    vphaddw %xmm7, %xmm11, %xmm1
    vphaddw %xmm9, %xmm14, %xmm3
    vphaddw %xmm3, %xmm0, %xmm15
    vphaddw %xmm15, %xmm2, %xmm9
    vphaddw %xmm1, %xmm14, %xmm12
    vphaddw %xmm12, %xmm8, %xmm15
    vphaddw (%rax), %xmm14, %xmm3
    vphaddw 8(%rsp), %xmm3, %xmm8
    vphaddw -200(%rbp), %xmm8, %xmm7
    vphaddw (%r12), %xmm7, %xmm11
    vphaddw 0x40(%r13), %xmm11, %xmm1
    vphaddw (%rax,%r9,8), %xmm1, %xmm14
    vphaddw 16(%r15,%rcx,2), %xmm14, %xmm3
    vphaddw -4(%rdx,%r14,4), %xmm3, %xmm8
    vphaddw %ymm7, %ymm2, %ymm1
    vphaddw %ymm9, %ymm6, %ymm3
    vphaddw %ymm3, %ymm8, %ymm7
    vphaddw %ymm15, %ymm11, %ymm1
    vphaddw %ymm1, %ymm6, %ymm12
    vphaddw %ymm12, %ymm0, %ymm15
    vphaddw %ymm7, %ymm11, %ymm9
    vphaddw %ymm9, %ymm14, %ymm12
    vphaddw (%rax), %ymm14, %ymm3
    vphaddw 8(%rsp), %ymm3, %ymm8
    vphaddw -200(%rbp), %ymm8, %ymm7
    vphaddw (%r12), %ymm7, %ymm11
    vphaddw 0x40(%r13), %ymm11, %ymm1
    vphaddw (%rax,%r9,8), %ymm1, %ymm14
    vphaddw 16(%r15,%rcx,2), %ymm14, %ymm3
    vphaddw -4(%rdx,%r14,4), %ymm3, %ymm8
    vphaddd %xmm3, %xmm0, %xmm7
    vphaddd %xmm15, %xmm2, %xmm1
    vphaddd %xmm1, %xmm14, %xmm3
    vphaddd %xmm12, %xmm8, %xmm7
    vphaddd %xmm7, %xmm2, %xmm9
    vphaddd %xmm9, %xmm6, %xmm12
    vphaddd %xmm3, %xmm8, %xmm15
    vphaddd %xmm15, %xmm11, %xmm9
    vphaddd (%rax), %xmm14, %xmm3
    vphaddd 8(%rsp), %xmm3, %xmm8
    vphaddd -200(%rbp), %xmm8, %xmm7
    vphaddd (%r12), %xmm7, %xmm11
    vphaddd 0x40(%r13), %xmm11, %xmm1
    vphaddd (%rax,%r9,8), %xmm1, %xmm14
    vphaddd 16(%r15,%rcx,2), %xmm14, %xmm3
    vphaddd -4(%rdx,%r14,4), %xmm3, %xmm8
    vphaddd %ymm1, %ymm6, %ymm3
    vphaddd %ymm12, %ymm0, %ymm7
    vphaddd %ymm7, %ymm11, %ymm1
    vphaddd %ymm9, %ymm14, %ymm3
    vphaddd %ymm3, %ymm0, %ymm15
    vphaddd %ymm15, %ymm2, %ymm9
    vphaddd %ymm1, %ymm14, %ymm12
    vphaddd %ymm12, %ymm8, %ymm15
    vphaddd (%rax), %ymm14, %ymm3
    vphaddd 8(%rsp), %ymm3, %ymm8
    vphaddd -200(%rbp), %ymm8, %ymm7
    vphaddd (%r12), %ymm7, %ymm11
    vphaddd 0x40(%r13), %ymm11, %ymm1
    vphaddd (%rax,%r9,8), %ymm1, %ymm14
    vphaddd 16(%r15,%rcx,2), %ymm14, %ymm3
    vphaddd -4(%rdx,%r14,4), %ymm3, %ymm8
    vphaddsw %xmm7, %xmm2, %xmm1
    vphaddsw %xmm9, %xmm6, %xmm3
    vphaddsw %xmm3, %xmm8, %xmm7
    vphaddsw %xmm15, %xmm11, %xmm1
    vphaddsw %xmm1, %xmm6, %xmm12
    vphaddsw %xmm12, %xmm0, %xmm15
    vphaddsw %xmm7, %xmm11, %xmm9
    vphaddsw %xmm9, %xmm14, %xmm12
    vphaddsw (%rax), %xmm14, %xmm3
    vphaddsw 8(%rsp), %xmm3, %xmm8
    vphaddsw -200(%rbp), %xmm8, %xmm7
    vphaddsw (%r12), %xmm7, %xmm11
    vphaddsw 0x40(%r13), %xmm11, %xmm1
    vphaddsw (%rax,%r9,8), %xmm1, %xmm14
    vphaddsw 16(%r15,%rcx,2), %xmm14, %xmm3
    vphaddsw -4(%rdx,%r14,4), %xmm3, %xmm8
    vphaddsw %ymm3, %ymm0, %ymm7
    vphaddsw %ymm15, %ymm2, %ymm1
    vphaddsw %ymm1, %ymm14, %ymm3
    vphaddsw %ymm12, %ymm8, %ymm7
    vphaddsw %ymm7, %ymm2, %ymm9
    vphaddsw %ymm9, %ymm6, %ymm12
    vphaddsw %ymm3, %ymm8, %ymm15
    vphaddsw %ymm15, %ymm11, %ymm9
    vphaddsw (%rax), %ymm14, %ymm3
    vphaddsw 8(%rsp), %ymm3, %ymm8
    vphaddsw -200(%rbp), %ymm8, %ymm7
    vphaddsw (%r12), %ymm7, %ymm11
    vphaddsw 0x40(%r13), %ymm11, %ymm1
    vphaddsw (%rax,%r9,8), %ymm1, %ymm14
    vphaddsw 16(%r15,%rcx,2), %ymm14, %ymm3
    vphaddsw -4(%rdx,%r14,4), %ymm3, %ymm8
    vpmaddubsw %xmm1, %xmm6, %xmm3
    vpmaddubsw %xmm12, %xmm0, %xmm7
    vpmaddubsw %xmm7, %xmm11, %xmm1
    vpmaddubsw %xmm9, %xmm14, %xmm3
    vpmaddubsw %xmm3, %xmm0, %xmm15
    vpmaddubsw %xmm15, %xmm2, %xmm9
    vpmaddubsw %xmm1, %xmm14, %xmm12
    vpmaddubsw %xmm12, %xmm8, %xmm15
    vpmaddubsw (%rax), %xmm14, %xmm3
    vpmaddubsw 8(%rsp), %xmm3, %xmm8
    vpmaddubsw -200(%rbp), %xmm8, %xmm7
    vpmaddubsw (%r12), %xmm7, %xmm11
    vpmaddubsw 0x40(%r13), %xmm11, %xmm1
    vpmaddubsw (%rax,%r9,8), %xmm1, %xmm14
    vpmaddubsw 16(%r15,%rcx,2), %xmm14, %xmm3
    vpmaddubsw -4(%rdx,%r14,4), %xmm3, %xmm8
    vpmaddubsw %ymm7, %ymm2, %ymm1
    vpmaddubsw %ymm9, %ymm6, %ymm3
    vpmaddubsw %ymm3, %ymm8, %ymm7
    vpmaddubsw %ymm15, %ymm11, %ymm1
    vpmaddubsw %ymm1, %ymm6, %ymm12
    vpmaddubsw %ymm12, %ymm0, %ymm15
    vpmaddubsw %ymm7, %ymm11, %ymm9
    vpmaddubsw %ymm9, %ymm14, %ymm12
    vpmaddubsw (%rax), %ymm14, %ymm3
    vpmaddubsw 8(%rsp), %ymm3, %ymm8
    vpmaddubsw -200(%rbp), %ymm8, %ymm7
    vpmaddubsw (%r12), %ymm7, %ymm11
    vpmaddubsw 0x40(%r13), %ymm11, %ymm1
    vpmaddubsw (%rax,%r9,8), %ymm1, %ymm14
    vpmaddubsw 16(%r15,%rcx,2), %ymm14, %ymm3
    vpmaddubsw -4(%rdx,%r14,4), %ymm3, %ymm8
    vphsubw %xmm3, %xmm0, %xmm7
    vphsubw %xmm15, %xmm2, %xmm1
    vphsubw %xmm1, %xmm14, %xmm3
    vphsubw %xmm12, %xmm8, %xmm7
    vphsubw %xmm7, %xmm2, %xmm9
    vphsubw %xmm9, %xmm6, %xmm12
    vphsubw %xmm3, %xmm8, %xmm15
    vphsubw %xmm15, %xmm11, %xmm9
    vphsubw (%rax), %xmm14, %xmm3
    vphsubw 8(%rsp), %xmm3, %xmm8
    vphsubw -200(%rbp), %xmm8, %xmm7
    vphsubw (%r12), %xmm7, %xmm11
    vphsubw 0x40(%r13), %xmm11, %xmm1
    vphsubw (%rax,%r9,8), %xmm1, %xmm14
    vphsubw 16(%r15,%rcx,2), %xmm14, %xmm3
    vphsubw -4(%rdx,%r14,4), %xmm3, %xmm8
    vphsubw %ymm1, %ymm6, %ymm3
    vphsubw %ymm12, %ymm0, %ymm7
    vphsubw %ymm7, %ymm11, %ymm1
    vphsubw %ymm9, %ymm14, %ymm3
    vphsubw %ymm3, %ymm0, %ymm15
    vphsubw %ymm15, %ymm2, %ymm9
    vphsubw %ymm1, %ymm14, %ymm12
    vphsubw %ymm12, %ymm8, %ymm15
    vphsubw (%rax), %ymm14, %ymm3
    vphsubw 8(%rsp), %ymm3, %ymm8
    vphsubw -200(%rbp), %ymm8, %ymm7
    vphsubw (%r12), %ymm7, %ymm11
    vphsubw 0x40(%r13), %ymm11, %ymm1
    vphsubw (%rax,%r9,8), %ymm1, %ymm14
    vphsubw 16(%r15,%rcx,2), %ymm14, %ymm3
    vphsubw -4(%rdx,%r14,4), %ymm3, %ymm8
    vphsubd %xmm7, %xmm2, %xmm1
    vphsubd %xmm9, %xmm6, %xmm3
    vphsubd %xmm3, %xmm8, %xmm7
    vphsubd %xmm15, %xmm11, %xmm1
    vphsubd %xmm1, %xmm6, %xmm12
    vphsubd %xmm12, %xmm0, %xmm15
    vphsubd %xmm7, %xmm11, %xmm9
    vphsubd %xmm9, %xmm14, %xmm12
    vphsubd (%rax), %xmm14, %xmm3
    vphsubd 8(%rsp), %xmm3, %xmm8
    vphsubd -200(%rbp), %xmm8, %xmm7
    vphsubd (%r12), %xmm7, %xmm11
    vphsubd 0x40(%r13), %xmm11, %xmm1
    vphsubd (%rax,%r9,8), %xmm1, %xmm14
    vphsubd 16(%r15,%rcx,2), %xmm14, %xmm3
    vphsubd -4(%rdx,%r14,4), %xmm3, %xmm8
    vphsubd %ymm3, %ymm0, %ymm7
    vphsubd %ymm15, %ymm2, %ymm1
    vphsubd %ymm1, %ymm14, %ymm3
    vphsubd %ymm12, %ymm8, %ymm7
    vphsubd %ymm7, %ymm2, %ymm9
    vphsubd %ymm9, %ymm6, %ymm12
    vphsubd %ymm3, %ymm8, %ymm15
    vphsubd %ymm15, %ymm11, %ymm9
    vphsubd (%rax), %ymm14, %ymm3
    vphsubd 8(%rsp), %ymm3, %ymm8
    vphsubd -200(%rbp), %ymm8, %ymm7
    vphsubd (%r12), %ymm7, %ymm11
    vphsubd 0x40(%r13), %ymm11, %ymm1
    vphsubd (%rax,%r9,8), %ymm1, %ymm14
    vphsubd 16(%r15,%rcx,2), %ymm14, %ymm3
    vphsubd -4(%rdx,%r14,4), %ymm3, %ymm8
    vphsubsw %xmm1, %xmm6, %xmm3
    vphsubsw %xmm12, %xmm0, %xmm7
    vphsubsw %xmm7, %xmm11, %xmm1
    vphsubsw %xmm9, %xmm14, %xmm3
    vphsubsw %xmm3, %xmm0, %xmm15
    vphsubsw %xmm15, %xmm2, %xmm9
    vphsubsw %xmm1, %xmm14, %xmm12
    vphsubsw %xmm12, %xmm8, %xmm15
    vphsubsw (%rax), %xmm14, %xmm3
    vphsubsw 8(%rsp), %xmm3, %xmm8
    vphsubsw -200(%rbp), %xmm8, %xmm7
    vphsubsw (%r12), %xmm7, %xmm11
    vphsubsw 0x40(%r13), %xmm11, %xmm1
    vphsubsw (%rax,%r9,8), %xmm1, %xmm14
    vphsubsw 16(%r15,%rcx,2), %xmm14, %xmm3
    vphsubsw -4(%rdx,%r14,4), %xmm3, %xmm8
    vphsubsw %ymm7, %ymm2, %ymm1
    vphsubsw %ymm9, %ymm6, %ymm3
    vphsubsw %ymm3, %ymm8, %ymm7
    vphsubsw %ymm15, %ymm11, %ymm1
    vphsubsw %ymm1, %ymm6, %ymm12
    vphsubsw %ymm12, %ymm0, %ymm15
    vphsubsw %ymm7, %ymm11, %ymm9
    vphsubsw %ymm9, %ymm14, %ymm12
    vphsubsw (%rax), %ymm14, %ymm3
    vphsubsw 8(%rsp), %ymm3, %ymm8
    vphsubsw -200(%rbp), %ymm8, %ymm7
    vphsubsw (%r12), %ymm7, %ymm11
    vphsubsw 0x40(%r13), %ymm11, %ymm1
    vphsubsw (%rax,%r9,8), %ymm1, %ymm14
    vphsubsw 16(%r15,%rcx,2), %ymm14, %ymm3
    vphsubsw -4(%rdx,%r14,4), %ymm3, %ymm8
    vpsignb %xmm3, %xmm0, %xmm7
    vpsignb %xmm15, %xmm2, %xmm1
    vpsignb %xmm1, %xmm14, %xmm3
    vpsignb %xmm12, %xmm8, %xmm7
    vpsignb %xmm7, %xmm2, %xmm9
    vpsignb %xmm9, %xmm6, %xmm12
    vpsignb %xmm3, %xmm8, %xmm15
    vpsignb %xmm15, %xmm11, %xmm9
    vpsignb (%rax), %xmm14, %xmm3
    vpsignb 8(%rsp), %xmm3, %xmm8
    vpsignb -200(%rbp), %xmm8, %xmm7
    vpsignb (%r12), %xmm7, %xmm11
    vpsignb 0x40(%r13), %xmm11, %xmm1
    vpsignb (%rax,%r9,8), %xmm1, %xmm14
    vpsignb 16(%r15,%rcx,2), %xmm14, %xmm3
    vpsignb -4(%rdx,%r14,4), %xmm3, %xmm8
    vpsignb %ymm1, %ymm6, %ymm3
    vpsignb %ymm12, %ymm0, %ymm7
    vpsignb %ymm7, %ymm11, %ymm1
    vpsignb %ymm9, %ymm14, %ymm3
    vpsignb %ymm3, %ymm0, %ymm15
    vpsignb %ymm15, %ymm2, %ymm9
    vpsignb %ymm1, %ymm14, %ymm12
    vpsignb %ymm12, %ymm8, %ymm15
    vpsignb (%rax), %ymm14, %ymm3
    vpsignb 8(%rsp), %ymm3, %ymm8
    vpsignb -200(%rbp), %ymm8, %ymm7
    vpsignb (%r12), %ymm7, %ymm11
    vpsignb 0x40(%r13), %ymm11, %ymm1
    vpsignb (%rax,%r9,8), %ymm1, %ymm14
    vpsignb 16(%r15,%rcx,2), %ymm14, %ymm3
    vpsignb -4(%rdx,%r14,4), %ymm3, %ymm8
    vpsignw %xmm7, %xmm2, %xmm1
    vpsignw %xmm9, %xmm6, %xmm3
    vpsignw %xmm3, %xmm8, %xmm7
    vpsignw %xmm15, %xmm11, %xmm1
    vpsignw %xmm1, %xmm6, %xmm12
    vpsignw %xmm12, %xmm0, %xmm15
    vpsignw %xmm7, %xmm11, %xmm9
    vpsignw %xmm9, %xmm14, %xmm12
    vpsignw (%rax), %xmm14, %xmm3
    vpsignw 8(%rsp), %xmm3, %xmm8
    vpsignw -200(%rbp), %xmm8, %xmm7
    vpsignw (%r12), %xmm7, %xmm11
    vpsignw 0x40(%r13), %xmm11, %xmm1
    vpsignw (%rax,%r9,8), %xmm1, %xmm14
    vpsignw 16(%r15,%rcx,2), %xmm14, %xmm3
    vpsignw -4(%rdx,%r14,4), %xmm3, %xmm8
    vpsignw %ymm3, %ymm0, %ymm7
    vpsignw %ymm15, %ymm2, %ymm1
    vpsignw %ymm1, %ymm14, %ymm3
    vpsignw %ymm12, %ymm8, %ymm7
    vpsignw %ymm7, %ymm2, %ymm9
    vpsignw %ymm9, %ymm6, %ymm12
    vpsignw %ymm3, %ymm8, %ymm15
    vpsignw %ymm15, %ymm11, %ymm9
    vpsignw (%rax), %ymm14, %ymm3
    vpsignw 8(%rsp), %ymm3, %ymm8
    vpsignw -200(%rbp), %ymm8, %ymm7
    vpsignw (%r12), %ymm7, %ymm11
    vpsignw 0x40(%r13), %ymm11, %ymm1
    vpsignw (%rax,%r9,8), %ymm1, %ymm14
    vpsignw 16(%r15,%rcx,2), %ymm14, %ymm3
    vpsignw -4(%rdx,%r14,4), %ymm3, %ymm8
    vpsignd %xmm1, %xmm6, %xmm3
    vpsignd %xmm12, %xmm0, %xmm7
    vpsignd %xmm7, %xmm11, %xmm1
    vpsignd %xmm9, %xmm14, %xmm3
    vpsignd %xmm3, %xmm0, %xmm15
    vpsignd %xmm15, %xmm2, %xmm9
    vpsignd %xmm1, %xmm14, %xmm12
    vpsignd %xmm12, %xmm8, %xmm15
    vpsignd (%rax), %xmm14, %xmm3
    vpsignd 8(%rsp), %xmm3, %xmm8
    vpsignd -200(%rbp), %xmm8, %xmm7
    vpsignd (%r12), %xmm7, %xmm11
    vpsignd 0x40(%r13), %xmm11, %xmm1
    vpsignd (%rax,%r9,8), %xmm1, %xmm14
    vpsignd 16(%r15,%rcx,2), %xmm14, %xmm3
    vpsignd -4(%rdx,%r14,4), %xmm3, %xmm8
    vpsignd %ymm7, %ymm2, %ymm1
    vpsignd %ymm9, %ymm6, %ymm3
    vpsignd %ymm3, %ymm8, %ymm7
    vpsignd %ymm15, %ymm11, %ymm1
    vpsignd %ymm1, %ymm6, %ymm12
    vpsignd %ymm12, %ymm0, %ymm15
    vpsignd %ymm7, %ymm11, %ymm9
    vpsignd %ymm9, %ymm14, %ymm12
    vpsignd (%rax), %ymm14, %ymm3
    vpsignd 8(%rsp), %ymm3, %ymm8
    vpsignd -200(%rbp), %ymm8, %ymm7
    vpsignd (%r12), %ymm7, %ymm11
    vpsignd 0x40(%r13), %ymm11, %ymm1
    vpsignd (%rax,%r9,8), %ymm1, %ymm14
    vpsignd 16(%r15,%rcx,2), %ymm14, %ymm3
    vpsignd -4(%rdx,%r14,4), %ymm3, %ymm8
    vpmulhrsw %xmm3, %xmm0, %xmm7
    vpmulhrsw %xmm15, %xmm2, %xmm1
    vpmulhrsw %xmm1, %xmm14, %xmm3
    vpmulhrsw %xmm12, %xmm8, %xmm7
    vpmulhrsw %xmm7, %xmm2, %xmm9
    vpmulhrsw %xmm9, %xmm6, %xmm12
    vpmulhrsw %xmm3, %xmm8, %xmm15
    vpmulhrsw %xmm15, %xmm11, %xmm9
    vpmulhrsw (%rax), %xmm14, %xmm3
    vpmulhrsw 8(%rsp), %xmm3, %xmm8
    vpmulhrsw -200(%rbp), %xmm8, %xmm7
    vpmulhrsw (%r12), %xmm7, %xmm11
    vpmulhrsw 0x40(%r13), %xmm11, %xmm1
    vpmulhrsw (%rax,%r9,8), %xmm1, %xmm14
    vpmulhrsw 16(%r15,%rcx,2), %xmm14, %xmm3
    vpmulhrsw -4(%rdx,%r14,4), %xmm3, %xmm8
    vpmulhrsw %ymm1, %ymm6, %ymm3
    vpmulhrsw %ymm12, %ymm0, %ymm7
    vpmulhrsw %ymm7, %ymm11, %ymm1
    vpmulhrsw %ymm9, %ymm14, %ymm3
    vpmulhrsw %ymm3, %ymm0, %ymm15
    vpmulhrsw %ymm15, %ymm2, %ymm9
    vpmulhrsw %ymm1, %ymm14, %ymm12
    vpmulhrsw %ymm12, %ymm8, %ymm15
    vpmulhrsw (%rax), %ymm14, %ymm3
    vpmulhrsw 8(%rsp), %ymm3, %ymm8
    vpmulhrsw -200(%rbp), %ymm8, %ymm7
    vpmulhrsw (%r12), %ymm7, %ymm11
    vpmulhrsw 0x40(%r13), %ymm11, %ymm1
    vpmulhrsw (%rax,%r9,8), %ymm1, %ymm14
    vpmulhrsw 16(%r15,%rcx,2), %ymm14, %ymm3
    vpmulhrsw -4(%rdx,%r14,4), %ymm3, %ymm8
    vpmuldq %xmm7, %xmm2, %xmm1
    vpmuldq %xmm9, %xmm6, %xmm3
    vpmuldq %xmm3, %xmm8, %xmm7
    vpmuldq %xmm15, %xmm11, %xmm1
    vpmuldq %xmm1, %xmm6, %xmm12
    vpmuldq %xmm12, %xmm0, %xmm15
    vpmuldq %xmm7, %xmm11, %xmm9
    vpmuldq %xmm9, %xmm14, %xmm12
    vpmuldq (%rax), %xmm14, %xmm3
    vpmuldq 8(%rsp), %xmm3, %xmm8
    vpmuldq -200(%rbp), %xmm8, %xmm7
    vpmuldq (%r12), %xmm7, %xmm11
    vpmuldq 0x40(%r13), %xmm11, %xmm1
    vpmuldq (%rax,%r9,8), %xmm1, %xmm14
    vpmuldq 16(%r15,%rcx,2), %xmm14, %xmm3
    vpmuldq -4(%rdx,%r14,4), %xmm3, %xmm8
    vpmuldq %ymm3, %ymm0, %ymm7
    vpmuldq %ymm15, %ymm2, %ymm1
    vpmuldq %ymm1, %ymm14, %ymm3
    vpmuldq %ymm12, %ymm8, %ymm7
    vpmuldq %ymm7, %ymm2, %ymm9
    vpmuldq %ymm9, %ymm6, %ymm12
    vpmuldq %ymm3, %ymm8, %ymm15
    vpmuldq %ymm15, %ymm11, %ymm9
    vpmuldq (%rax), %ymm14, %ymm3
    vpmuldq 8(%rsp), %ymm3, %ymm8
    vpmuldq -200(%rbp), %ymm8, %ymm7
    vpmuldq (%r12), %ymm7, %ymm11
    vpmuldq 0x40(%r13), %ymm11, %ymm1
    vpmuldq (%rax,%r9,8), %ymm1, %ymm14
    vpmuldq 16(%r15,%rcx,2), %ymm14, %ymm3
    vpmuldq -4(%rdx,%r14,4), %ymm3, %ymm8
    vpcmpeqq %xmm1, %xmm6, %xmm3
    vpcmpeqq %xmm12, %xmm0, %xmm7
    vpcmpeqq %xmm7, %xmm11, %xmm1
    vpcmpeqq %xmm9, %xmm14, %xmm3
    vpcmpeqq %xmm3, %xmm0, %xmm15
    vpcmpeqq %xmm15, %xmm2, %xmm9
    vpcmpeqq %xmm1, %xmm14, %xmm12
    vpcmpeqq %xmm12, %xmm8, %xmm15
    vpcmpeqq (%rax), %xmm14, %xmm3
    vpcmpeqq 8(%rsp), %xmm3, %xmm8
    vpcmpeqq -200(%rbp), %xmm8, %xmm7
    vpcmpeqq (%r12), %xmm7, %xmm11
    vpcmpeqq 0x40(%r13), %xmm11, %xmm1
    vpcmpeqq (%rax,%r9,8), %xmm1, %xmm14
    vpcmpeqq 16(%r15,%rcx,2), %xmm14, %xmm3
    vpcmpeqq -4(%rdx,%r14,4), %xmm3, %xmm8
    vpcmpeqq %ymm7, %ymm2, %ymm1
    vpcmpeqq %ymm9, %ymm6, %ymm3
    vpcmpeqq %ymm3, %ymm8, %ymm7
    vpcmpeqq %ymm15, %ymm11, %ymm1
    vpcmpeqq %ymm1, %ymm6, %ymm12
    vpcmpeqq %ymm12, %ymm0, %ymm15
    vpcmpeqq %ymm7, %ymm11, %ymm9
    vpcmpeqq %ymm9, %ymm14, %ymm12
    vpcmpeqq (%rax), %ymm14, %ymm3
    vpcmpeqq 8(%rsp), %ymm3, %ymm8
    vpcmpeqq -200(%rbp), %ymm8, %ymm7
    vpcmpeqq (%r12), %ymm7, %ymm11
    vpcmpeqq 0x40(%r13), %ymm11, %ymm1
    vpcmpeqq (%rax,%r9,8), %ymm1, %ymm14
    vpcmpeqq 16(%r15,%rcx,2), %ymm14, %ymm3
    vpcmpeqq -4(%rdx,%r14,4), %ymm3, %ymm8
    vpackusdw %xmm3, %xmm0, %xmm7
    vpackusdw %xmm15, %xmm2, %xmm1
    vpackusdw %xmm1, %xmm14, %xmm3
    vpackusdw %xmm12, %xmm8, %xmm7
    vpackusdw %xmm7, %xmm2, %xmm9
    vpackusdw %xmm9, %xmm6, %xmm12
    vpackusdw %xmm3, %xmm8, %xmm15
    vpackusdw %xmm15, %xmm11, %xmm9
    vpackusdw (%rax), %xmm14, %xmm3
    vpackusdw 8(%rsp), %xmm3, %xmm8
    vpackusdw -200(%rbp), %xmm8, %xmm7
    vpackusdw (%r12), %xmm7, %xmm11
    vpackusdw 0x40(%r13), %xmm11, %xmm1
    vpackusdw (%rax,%r9,8), %xmm1, %xmm14
    vpackusdw 16(%r15,%rcx,2), %xmm14, %xmm3
    vpackusdw -4(%rdx,%r14,4), %xmm3, %xmm8
    vpackusdw %ymm1, %ymm6, %ymm3
    vpackusdw %ymm12, %ymm0, %ymm7
    vpackusdw %ymm7, %ymm11, %ymm1
    vpackusdw %ymm9, %ymm14, %ymm3
    vpackusdw %ymm3, %ymm0, %ymm15
    vpackusdw %ymm15, %ymm2, %ymm9
    vpackusdw %ymm1, %ymm14, %ymm12
    vpackusdw %ymm12, %ymm8, %ymm15
    vpackusdw (%rax), %ymm14, %ymm3
    vpackusdw 8(%rsp), %ymm3, %ymm8
    vpackusdw -200(%rbp), %ymm8, %ymm7
    vpackusdw (%r12), %ymm7, %ymm11
    vpackusdw 0x40(%r13), %ymm11, %ymm1
    vpackusdw (%rax,%r9,8), %ymm1, %ymm14
    vpackusdw 16(%r15,%rcx,2), %ymm14, %ymm3
    vpackusdw -4(%rdx,%r14,4), %ymm3, %ymm8
    vpcmpgtq %xmm7, %xmm2, %xmm1
    vpcmpgtq %xmm9, %xmm6, %xmm3
    vpcmpgtq %xmm3, %xmm8, %xmm7
    vpcmpgtq %xmm15, %xmm11, %xmm1
    vpcmpgtq %xmm1, %xmm6, %xmm12
    vpcmpgtq %xmm12, %xmm0, %xmm15
    vpcmpgtq %xmm7, %xmm11, %xmm9
    vpcmpgtq %xmm9, %xmm14, %xmm12
    vpcmpgtq (%rax), %xmm14, %xmm3
    vpcmpgtq 8(%rsp), %xmm3, %xmm8
    vpcmpgtq -200(%rbp), %xmm8, %xmm7
    vpcmpgtq (%r12), %xmm7, %xmm11
    vpcmpgtq 0x40(%r13), %xmm11, %xmm1
    vpcmpgtq (%rax,%r9,8), %xmm1, %xmm14
    vpcmpgtq 16(%r15,%rcx,2), %xmm14, %xmm3
    vpcmpgtq -4(%rdx,%r14,4), %xmm3, %xmm8
    vpcmpgtq %ymm3, %ymm0, %ymm7
    vpcmpgtq %ymm15, %ymm2, %ymm1
    vpcmpgtq %ymm1, %ymm14, %ymm3
    vpcmpgtq %ymm12, %ymm8, %ymm7
    vpcmpgtq %ymm7, %ymm2, %ymm9
    vpcmpgtq %ymm9, %ymm6, %ymm12
    vpcmpgtq %ymm3, %ymm8, %ymm15
    vpcmpgtq %ymm15, %ymm11, %ymm9
    vpcmpgtq (%rax), %ymm14, %ymm3
    vpcmpgtq 8(%rsp), %ymm3, %ymm8
    vpcmpgtq -200(%rbp), %ymm8, %ymm7
    vpcmpgtq (%r12), %ymm7, %ymm11
    vpcmpgtq 0x40(%r13), %ymm11, %ymm1
    vpcmpgtq (%rax,%r9,8), %ymm1, %ymm14
    vpcmpgtq 16(%r15,%rcx,2), %ymm14, %ymm3
    vpcmpgtq -4(%rdx,%r14,4), %ymm3, %ymm8
    vpminsb %xmm1, %xmm6, %xmm3
    vpminsb %xmm12, %xmm0, %xmm7
    vpminsb %xmm7, %xmm11, %xmm1
    vpminsb %xmm9, %xmm14, %xmm3
    vpminsb %xmm3, %xmm0, %xmm15
    vpminsb %xmm15, %xmm2, %xmm9
    vpminsb %xmm1, %xmm14, %xmm12
    vpminsb %xmm12, %xmm8, %xmm15
    vpminsb (%rax), %xmm14, %xmm3
    vpminsb 8(%rsp), %xmm3, %xmm8
    vpminsb -200(%rbp), %xmm8, %xmm7
    vpminsb (%r12), %xmm7, %xmm11
    vpminsb 0x40(%r13), %xmm11, %xmm1
    vpminsb (%rax,%r9,8), %xmm1, %xmm14
    vpminsb 16(%r15,%rcx,2), %xmm14, %xmm3
    vpminsb -4(%rdx,%r14,4), %xmm3, %xmm8
    vpminsb %ymm7, %ymm2, %ymm1
    vpminsb %ymm9, %ymm6, %ymm3
    vpminsb %ymm3, %ymm8, %ymm7
    vpminsb %ymm15, %ymm11, %ymm1
    vpminsb %ymm1, %ymm6, %ymm12
    vpminsb %ymm12, %ymm0, %ymm15
    vpminsb %ymm7, %ymm11, %ymm9
    vpminsb %ymm9, %ymm14, %ymm12
    vpminsb (%rax), %ymm14, %ymm3
    vpminsb 8(%rsp), %ymm3, %ymm8
    vpminsb -200(%rbp), %ymm8, %ymm7
    vpminsb (%r12), %ymm7, %ymm11
    vpminsb 0x40(%r13), %ymm11, %ymm1
    vpminsb (%rax,%r9,8), %ymm1, %ymm14
    vpminsb 16(%r15,%rcx,2), %ymm14, %ymm3
    vpminsb -4(%rdx,%r14,4), %ymm3, %ymm8
    vpminsd %xmm3, %xmm0, %xmm7
    vpminsd %xmm15, %xmm2, %xmm1
    vpminsd %xmm1, %xmm14, %xmm3
    vpminsd %xmm12, %xmm8, %xmm7
    vpminsd %xmm7, %xmm2, %xmm9
    vpminsd %xmm9, %xmm6, %xmm12
    vpminsd %xmm3, %xmm8, %xmm15
    vpminsd %xmm15, %xmm11, %xmm9
    vpminsd (%rax), %xmm14, %xmm3
    vpminsd 8(%rsp), %xmm3, %xmm8
    vpminsd -200(%rbp), %xmm8, %xmm7
    vpminsd (%r12), %xmm7, %xmm11
    vpminsd 0x40(%r13), %xmm11, %xmm1
    vpminsd (%rax,%r9,8), %xmm1, %xmm14
    vpminsd 16(%r15,%rcx,2), %xmm14, %xmm3
    vpminsd -4(%rdx,%r14,4), %xmm3, %xmm8
    vpminsd %ymm1, %ymm6, %ymm3
    vpminsd %ymm12, %ymm0, %ymm7
    vpminsd %ymm7, %ymm11, %ymm1
    vpminsd %ymm9, %ymm14, %ymm3
    vpminsd %ymm3, %ymm0, %ymm15
    vpminsd %ymm15, %ymm2, %ymm9
    vpminsd %ymm1, %ymm14, %ymm12
    vpminsd %ymm12, %ymm8, %ymm15
    vpminsd (%rax), %ymm14, %ymm3
    vpminsd 8(%rsp), %ymm3, %ymm8
    vpminsd -200(%rbp), %ymm8, %ymm7
    vpminsd (%r12), %ymm7, %ymm11
    vpminsd 0x40(%r13), %ymm11, %ymm1
    vpminsd (%rax,%r9,8), %ymm1, %ymm14
    vpminsd 16(%r15,%rcx,2), %ymm14, %ymm3
    vpminsd -4(%rdx,%r14,4), %ymm3, %ymm8
    vpminuw %xmm7, %xmm2, %xmm1
    vpminuw %xmm9, %xmm6, %xmm3
    vpminuw %xmm3, %xmm8, %xmm7
    vpminuw %xmm15, %xmm11, %xmm1
    vpminuw %xmm1, %xmm6, %xmm12
    vpminuw %xmm12, %xmm0, %xmm15
    vpminuw %xmm7, %xmm11, %xmm9
    vpminuw %xmm9, %xmm14, %xmm12
    vpminuw (%rax), %xmm14, %xmm3
    vpminuw 8(%rsp), %xmm3, %xmm8
    vpminuw -200(%rbp), %xmm8, %xmm7
    vpminuw (%r12), %xmm7, %xmm11
    vpminuw 0x40(%r13), %xmm11, %xmm1
    vpminuw (%rax,%r9,8), %xmm1, %xmm14
    vpminuw 16(%r15,%rcx,2), %xmm14, %xmm3
    vpminuw -4(%rdx,%r14,4), %xmm3, %xmm8
    vpminuw %ymm3, %ymm0, %ymm7
    vpminuw %ymm15, %ymm2, %ymm1
    vpminuw %ymm1, %ymm14, %ymm3
    vpminuw %ymm12, %ymm8, %ymm7
    vpminuw %ymm7, %ymm2, %ymm9
    vpminuw %ymm9, %ymm6, %ymm12
    vpminuw %ymm3, %ymm8, %ymm15
    vpminuw %ymm15, %ymm11, %ymm9
    vpminuw (%rax), %ymm14, %ymm3
    vpminuw 8(%rsp), %ymm3, %ymm8
    vpminuw -200(%rbp), %ymm8, %ymm7
    vpminuw (%r12), %ymm7, %ymm11
    vpminuw 0x40(%r13), %ymm11, %ymm1
    vpminuw (%rax,%r9,8), %ymm1, %ymm14
    vpminuw 16(%r15,%rcx,2), %ymm14, %ymm3
    vpminuw -4(%rdx,%r14,4), %ymm3, %ymm8
    vpminud %xmm1, %xmm6, %xmm3
    vpminud %xmm12, %xmm0, %xmm7
    vpminud %xmm7, %xmm11, %xmm1
    vpminud %xmm9, %xmm14, %xmm3
    vpminud %xmm3, %xmm0, %xmm15
    vpminud %xmm15, %xmm2, %xmm9
    vpminud %xmm1, %xmm14, %xmm12
    vpminud %xmm12, %xmm8, %xmm15
    vpminud (%rax), %xmm14, %xmm3
    vpminud 8(%rsp), %xmm3, %xmm8
    vpminud -200(%rbp), %xmm8, %xmm7
    vpminud (%r12), %xmm7, %xmm11
    vpminud 0x40(%r13), %xmm11, %xmm1
    vpminud (%rax,%r9,8), %xmm1, %xmm14
    vpminud 16(%r15,%rcx,2), %xmm14, %xmm3
    vpminud -4(%rdx,%r14,4), %xmm3, %xmm8
    vpminud %ymm7, %ymm2, %ymm1
    vpminud %ymm9, %ymm6, %ymm3
    vpminud %ymm3, %ymm8, %ymm7
    vpminud %ymm15, %ymm11, %ymm1
    vpminud %ymm1, %ymm6, %ymm12
    vpminud %ymm12, %ymm0, %ymm15
    vpminud %ymm7, %ymm11, %ymm9
    vpminud %ymm9, %ymm14, %ymm12
    vpminud (%rax), %ymm14, %ymm3
    vpminud 8(%rsp), %ymm3, %ymm8
    vpminud -200(%rbp), %ymm8, %ymm7
    vpminud (%r12), %ymm7, %ymm11
    vpminud 0x40(%r13), %ymm11, %ymm1
    vpminud (%rax,%r9,8), %ymm1, %ymm14
    vpminud 16(%r15,%rcx,2), %ymm14, %ymm3
    vpminud -4(%rdx,%r14,4), %ymm3, %ymm8
    vpmaxsb %xmm3, %xmm0, %xmm7
    vpmaxsb %xmm15, %xmm2, %xmm1
    vpmaxsb %xmm1, %xmm14, %xmm3
    vpmaxsb %xmm12, %xmm8, %xmm7
    vpmaxsb %xmm7, %xmm2, %xmm9
    vpmaxsb %xmm9, %xmm6, %xmm12
    vpmaxsb %xmm3, %xmm8, %xmm15
    vpmaxsb %xmm15, %xmm11, %xmm9
    vpmaxsb (%rax), %xmm14, %xmm3
    vpmaxsb 8(%rsp), %xmm3, %xmm8
    vpmaxsb -200(%rbp), %xmm8, %xmm7
    vpmaxsb (%r12), %xmm7, %xmm11
    vpmaxsb 0x40(%r13), %xmm11, %xmm1
    vpmaxsb (%rax,%r9,8), %xmm1, %xmm14
    vpmaxsb 16(%r15,%rcx,2), %xmm14, %xmm3
    vpmaxsb -4(%rdx,%r14,4), %xmm3, %xmm8
    vpmaxsb %ymm1, %ymm6, %ymm3
    vpmaxsb %ymm12, %ymm0, %ymm7
    vpmaxsb %ymm7, %ymm11, %ymm1
    vpmaxsb %ymm9, %ymm14, %ymm3
    vpmaxsb %ymm3, %ymm0, %ymm15
    vpmaxsb %ymm15, %ymm2, %ymm9
    vpmaxsb %ymm1, %ymm14, %ymm12
    vpmaxsb %ymm12, %ymm8, %ymm15
    vpmaxsb (%rax), %ymm14, %ymm3
    vpmaxsb 8(%rsp), %ymm3, %ymm8
    vpmaxsb -200(%rbp), %ymm8, %ymm7
    vpmaxsb (%r12), %ymm7, %ymm11
    vpmaxsb 0x40(%r13), %ymm11, %ymm1
    vpmaxsb (%rax,%r9,8), %ymm1, %ymm14
    vpmaxsb 16(%r15,%rcx,2), %ymm14, %ymm3
    vpmaxsb -4(%rdx,%r14,4), %ymm3, %ymm8
    vpmaxsd %xmm7, %xmm2, %xmm1
    vpmaxsd %xmm9, %xmm6, %xmm3
    vpmaxsd %xmm3, %xmm8, %xmm7
    vpmaxsd %xmm15, %xmm11, %xmm1
    vpmaxsd %xmm1, %xmm6, %xmm12
    vpmaxsd %xmm12, %xmm0, %xmm15
    vpmaxsd %xmm7, %xmm11, %xmm9
    vpmaxsd %xmm9, %xmm14, %xmm12
    vpmaxsd (%rax), %xmm14, %xmm3
    vpmaxsd 8(%rsp), %xmm3, %xmm8
    vpmaxsd -200(%rbp), %xmm8, %xmm7
    vpmaxsd (%r12), %xmm7, %xmm11
    vpmaxsd 0x40(%r13), %xmm11, %xmm1
    vpmaxsd (%rax,%r9,8), %xmm1, %xmm14
    vpmaxsd 16(%r15,%rcx,2), %xmm14, %xmm3
    vpmaxsd -4(%rdx,%r14,4), %xmm3, %xmm8
    vpmaxsd %ymm3, %ymm0, %ymm7
    vpmaxsd %ymm15, %ymm2, %ymm1
    vpmaxsd %ymm1, %ymm14, %ymm3
    vpmaxsd %ymm12, %ymm8, %ymm7
    vpmaxsd %ymm7, %ymm2, %ymm9
    vpmaxsd %ymm9, %ymm6, %ymm12
    vpmaxsd %ymm3, %ymm8, %ymm15
    vpmaxsd %ymm15, %ymm11, %ymm9
    vpmaxsd (%rax), %ymm14, %ymm3
    vpmaxsd 8(%rsp), %ymm3, %ymm8
    vpmaxsd -200(%rbp), %ymm8, %ymm7
    vpmaxsd (%r12), %ymm7, %ymm11
    vpmaxsd 0x40(%r13), %ymm11, %ymm1
    vpmaxsd (%rax,%r9,8), %ymm1, %ymm14
    vpmaxsd 16(%r15,%rcx,2), %ymm14, %ymm3
    vpmaxsd -4(%rdx,%r14,4), %ymm3, %ymm8
    vpmaxuw %xmm1, %xmm6, %xmm3
    vpmaxuw %xmm12, %xmm0, %xmm7
    vpmaxuw %xmm7, %xmm11, %xmm1
    vpmaxuw %xmm9, %xmm14, %xmm3
    vpmaxuw %xmm3, %xmm0, %xmm15
    vpmaxuw %xmm15, %xmm2, %xmm9
    vpmaxuw %xmm1, %xmm14, %xmm12
    vpmaxuw %xmm12, %xmm8, %xmm15
    vpmaxuw (%rax), %xmm14, %xmm3
    vpmaxuw 8(%rsp), %xmm3, %xmm8
    vpmaxuw -200(%rbp), %xmm8, %xmm7
    vpmaxuw (%r12), %xmm7, %xmm11
    vpmaxuw 0x40(%r13), %xmm11, %xmm1
    vpmaxuw (%rax,%r9,8), %xmm1, %xmm14
    vpmaxuw 16(%r15,%rcx,2), %xmm14, %xmm3
    vpmaxuw -4(%rdx,%r14,4), %xmm3, %xmm8
    vpmaxuw %ymm7, %ymm2, %ymm1
    vpmaxuw %ymm9, %ymm6, %ymm3
    vpmaxuw %ymm3, %ymm8, %ymm7
    vpmaxuw %ymm15, %ymm11, %ymm1
    vpmaxuw %ymm1, %ymm6, %ymm12
    vpmaxuw %ymm12, %ymm0, %ymm15
    vpmaxuw %ymm7, %ymm11, %ymm9
    vpmaxuw %ymm9, %ymm14, %ymm12
    vpmaxuw (%rax), %ymm14, %ymm3
    vpmaxuw 8(%rsp), %ymm3, %ymm8
    vpmaxuw -200(%rbp), %ymm8, %ymm7
    vpmaxuw (%r12), %ymm7, %ymm11
    vpmaxuw 0x40(%r13), %ymm11, %ymm1
    vpmaxuw (%rax,%r9,8), %ymm1, %ymm14
    vpmaxuw 16(%r15,%rcx,2), %ymm14, %ymm3
    vpmaxuw -4(%rdx,%r14,4), %ymm3, %ymm8
    vpmaxud %xmm3, %xmm0, %xmm7
    vpmaxud %xmm15, %xmm2, %xmm1
    vpmaxud %xmm1, %xmm14, %xmm3
    vpmaxud %xmm12, %xmm8, %xmm7
    vpmaxud %xmm7, %xmm2, %xmm9
    vpmaxud %xmm9, %xmm6, %xmm12
    vpmaxud %xmm3, %xmm8, %xmm15
    vpmaxud %xmm15, %xmm11, %xmm9
    vpmaxud (%rax), %xmm14, %xmm3
    vpmaxud 8(%rsp), %xmm3, %xmm8
    vpmaxud -200(%rbp), %xmm8, %xmm7
    vpmaxud (%r12), %xmm7, %xmm11
    vpmaxud 0x40(%r13), %xmm11, %xmm1
    vpmaxud (%rax,%r9,8), %xmm1, %xmm14
    vpmaxud 16(%r15,%rcx,2), %xmm14, %xmm3
    vpmaxud -4(%rdx,%r14,4), %xmm3, %xmm8
    vpmaxud %ymm1, %ymm6, %ymm3
    vpmaxud %ymm12, %ymm0, %ymm7
    vpmaxud %ymm7, %ymm11, %ymm1
    vpmaxud %ymm9, %ymm14, %ymm3
    vpmaxud %ymm3, %ymm0, %ymm15
    vpmaxud %ymm15, %ymm2, %ymm9
    vpmaxud %ymm1, %ymm14, %ymm12
    vpmaxud %ymm12, %ymm8, %ymm15
    vpmaxud (%rax), %ymm14, %ymm3
    vpmaxud 8(%rsp), %ymm3, %ymm8
    vpmaxud -200(%rbp), %ymm8, %ymm7
    vpmaxud (%r12), %ymm7, %ymm11
    vpmaxud 0x40(%r13), %ymm11, %ymm1
    vpmaxud (%rax,%r9,8), %ymm1, %ymm14
    vpmaxud 16(%r15,%rcx,2), %ymm14, %ymm3
    vpmaxud -4(%rdx,%r14,4), %ymm3, %ymm8
    vpmulld %xmm7, %xmm2, %xmm1
    vpmulld %xmm9, %xmm6, %xmm3
    vpmulld %xmm3, %xmm8, %xmm7
    vpmulld %xmm15, %xmm11, %xmm1
    vpmulld %xmm1, %xmm6, %xmm12
    vpmulld %xmm12, %xmm0, %xmm15
    vpmulld %xmm7, %xmm11, %xmm9
    vpmulld %xmm9, %xmm14, %xmm12
    vpmulld (%rax), %xmm14, %xmm3
    vpmulld 8(%rsp), %xmm3, %xmm8
    vpmulld -200(%rbp), %xmm8, %xmm7
    vpmulld (%r12), %xmm7, %xmm11
    vpmulld 0x40(%r13), %xmm11, %xmm1
    vpmulld (%rax,%r9,8), %xmm1, %xmm14
    vpmulld 16(%r15,%rcx,2), %xmm14, %xmm3
    vpmulld -4(%rdx,%r14,4), %xmm3, %xmm8
    vpmulld %ymm3, %ymm0, %ymm7
    vpmulld %ymm15, %ymm2, %ymm1
    vpmulld %ymm1, %ymm14, %ymm3
    vpmulld %ymm12, %ymm8, %ymm7
    vpmulld %ymm7, %ymm2, %ymm9
    vpmulld %ymm9, %ymm6, %ymm12
    vpmulld %ymm3, %ymm8, %ymm15
    vpmulld %ymm15, %ymm11, %ymm9
    vpmulld (%rax), %ymm14, %ymm3
    vpmulld 8(%rsp), %ymm3, %ymm8
    vpmulld -200(%rbp), %ymm8, %ymm7
    vpmulld (%r12), %ymm7, %ymm11
    vpmulld 0x40(%r13), %ymm11, %ymm1
    vpmulld (%rax,%r9,8), %ymm1, %ymm14
    vpmulld 16(%r15,%rcx,2), %ymm14, %ymm3
    vpmulld -4(%rdx,%r14,4), %ymm3, %ymm8
    vpsrlvd %xmm1, %xmm6, %xmm3
    vpsrlvd %xmm12, %xmm0, %xmm7
    vpsrlvd %xmm7, %xmm11, %xmm1
    vpsrlvd %xmm9, %xmm14, %xmm3
    vpsrlvd %xmm3, %xmm0, %xmm15
    vpsrlvd %xmm15, %xmm2, %xmm9
    vpsrlvd %xmm1, %xmm14, %xmm12
    vpsrlvd %xmm12, %xmm8, %xmm15
    vpsrlvd (%rax), %xmm14, %xmm3
    vpsrlvd 8(%rsp), %xmm3, %xmm8
    vpsrlvd -200(%rbp), %xmm8, %xmm7
    vpsrlvd (%r12), %xmm7, %xmm11
    vpsrlvd 0x40(%r13), %xmm11, %xmm1
    vpsrlvd (%rax,%r9,8), %xmm1, %xmm14
    vpsrlvd 16(%r15,%rcx,2), %xmm14, %xmm3
    vpsrlvd -4(%rdx,%r14,4), %xmm3, %xmm8
    vpsrlvd %ymm7, %ymm2, %ymm1
    vpsrlvd %ymm9, %ymm6, %ymm3
    vpsrlvd %ymm3, %ymm8, %ymm7
    vpsrlvd %ymm15, %ymm11, %ymm1
    vpsrlvd %ymm1, %ymm6, %ymm12
    vpsrlvd %ymm12, %ymm0, %ymm15
    vpsrlvd %ymm7, %ymm11, %ymm9
    vpsrlvd %ymm9, %ymm14, %ymm12
    vpsrlvd (%rax), %ymm14, %ymm3
    vpsrlvd 8(%rsp), %ymm3, %ymm8
    vpsrlvd -200(%rbp), %ymm8, %ymm7
    vpsrlvd (%r12), %ymm7, %ymm11
    vpsrlvd 0x40(%r13), %ymm11, %ymm1
    vpsrlvd (%rax,%r9,8), %ymm1, %ymm14
    vpsrlvd 16(%r15,%rcx,2), %ymm14, %ymm3
    vpsrlvd -4(%rdx,%r14,4), %ymm3, %ymm8
    vpsravd %xmm3, %xmm0, %xmm7
    vpsravd %xmm15, %xmm2, %xmm1
    vpsravd %xmm1, %xmm14, %xmm3
    vpsravd %xmm12, %xmm8, %xmm7
    vpsravd %xmm7, %xmm2, %xmm9
    vpsravd %xmm9, %xmm6, %xmm12
    vpsravd %xmm3, %xmm8, %xmm15
    vpsravd %xmm15, %xmm11, %xmm9
    vpsravd (%rax), %xmm14, %xmm3
    vpsravd 8(%rsp), %xmm3, %xmm8
    vpsravd -200(%rbp), %xmm8, %xmm7
    vpsravd (%r12), %xmm7, %xmm11
    vpsravd 0x40(%r13), %xmm11, %xmm1
    vpsravd (%rax,%r9,8), %xmm1, %xmm14
    vpsravd 16(%r15,%rcx,2), %xmm14, %xmm3
    vpsravd -4(%rdx,%r14,4), %xmm3, %xmm8
    vpsravd %ymm1, %ymm6, %ymm3
    vpsravd %ymm12, %ymm0, %ymm7
    vpsravd %ymm7, %ymm11, %ymm1
    vpsravd %ymm9, %ymm14, %ymm3
    vpsravd %ymm3, %ymm0, %ymm15
    vpsravd %ymm15, %ymm2, %ymm9
    vpsravd %ymm1, %ymm14, %ymm12
    vpsravd %ymm12, %ymm8, %ymm15
    vpsravd (%rax), %ymm14, %ymm3
    vpsravd 8(%rsp), %ymm3, %ymm8
    vpsravd -200(%rbp), %ymm8, %ymm7
    vpsravd (%r12), %ymm7, %ymm11
    vpsravd 0x40(%r13), %ymm11, %ymm1
    vpsravd (%rax,%r9,8), %ymm1, %ymm14
    vpsravd 16(%r15,%rcx,2), %ymm14, %ymm3
    vpsravd -4(%rdx,%r14,4), %ymm3, %ymm8
    vpsllvd %xmm7, %xmm2, %xmm1
    vpsllvd %xmm9, %xmm6, %xmm3
    vpsllvd %xmm3, %xmm8, %xmm7
    vpsllvd %xmm15, %xmm11, %xmm1
    vpsllvd %xmm1, %xmm6, %xmm12
    vpsllvd %xmm12, %xmm0, %xmm15
    vpsllvd %xmm7, %xmm11, %xmm9
    vpsllvd %xmm9, %xmm14, %xmm12
    vpsllvd (%rax), %xmm14, %xmm3
    vpsllvd 8(%rsp), %xmm3, %xmm8
    vpsllvd -200(%rbp), %xmm8, %xmm7
    vpsllvd (%r12), %xmm7, %xmm11
    vpsllvd 0x40(%r13), %xmm11, %xmm1
    vpsllvd (%rax,%r9,8), %xmm1, %xmm14
    vpsllvd 16(%r15,%rcx,2), %xmm14, %xmm3
    vpsllvd -4(%rdx,%r14,4), %xmm3, %xmm8
    vpsllvd %ymm3, %ymm0, %ymm7
    vpsllvd %ymm15, %ymm2, %ymm1
    vpsllvd %ymm1, %ymm14, %ymm3
    vpsllvd %ymm12, %ymm8, %ymm7
    vpsllvd %ymm7, %ymm2, %ymm9
    vpsllvd %ymm9, %ymm6, %ymm12
    vpsllvd %ymm3, %ymm8, %ymm15
    vpsllvd %ymm15, %ymm11, %ymm9
    vpsllvd (%rax), %ymm14, %ymm3
    vpsllvd 8(%rsp), %ymm3, %ymm8
    vpsllvd -200(%rbp), %ymm8, %ymm7
    vpsllvd (%r12), %ymm7, %ymm11
    vpsllvd 0x40(%r13), %ymm11, %ymm1
    vpsllvd (%rax,%r9,8), %ymm1, %ymm14
    vpsllvd 16(%r15,%rcx,2), %ymm14, %ymm3
    vpsllvd -4(%rdx,%r14,4), %ymm3, %ymm8
    vpermilps %xmm1, %xmm6, %xmm3
    vpermilps %xmm12, %xmm0, %xmm7
    vpermilps %xmm7, %xmm11, %xmm1
    vpermilps %xmm9, %xmm14, %xmm3
    vpermilps %xmm3, %xmm0, %xmm15
    vpermilps %xmm15, %xmm2, %xmm9
    vpermilps %xmm1, %xmm14, %xmm12
    vpermilps %xmm12, %xmm8, %xmm15
    vpermilps (%rax), %xmm14, %xmm3
    vpermilps 8(%rsp), %xmm3, %xmm8
    vpermilps -200(%rbp), %xmm8, %xmm7
    vpermilps (%r12), %xmm7, %xmm11
    vpermilps 0x40(%r13), %xmm11, %xmm1
    vpermilps (%rax,%r9,8), %xmm1, %xmm14
    vpermilps 16(%r15,%rcx,2), %xmm14, %xmm3
    vpermilps -4(%rdx,%r14,4), %xmm3, %xmm8
    vpermilps %ymm7, %ymm2, %ymm1
    vpermilps %ymm9, %ymm6, %ymm3
    vpermilps %ymm3, %ymm8, %ymm7
    vpermilps %ymm15, %ymm11, %ymm1
    vpermilps %ymm1, %ymm6, %ymm12
    vpermilps %ymm12, %ymm0, %ymm15
    vpermilps %ymm7, %ymm11, %ymm9
    vpermilps %ymm9, %ymm14, %ymm12
    vpermilps (%rax), %ymm14, %ymm3
    vpermilps 8(%rsp), %ymm3, %ymm8
    vpermilps -200(%rbp), %ymm8, %ymm7
    vpermilps (%r12), %ymm7, %ymm11
    vpermilps 0x40(%r13), %ymm11, %ymm1
    vpermilps (%rax,%r9,8), %ymm1, %ymm14
    vpermilps 16(%r15,%rcx,2), %ymm14, %ymm3
    vpermilps -4(%rdx,%r14,4), %ymm3, %ymm8
    vpermilpd %xmm3, %xmm0, %xmm7
    vpermilpd %xmm15, %xmm2, %xmm1
    vpermilpd %xmm1, %xmm14, %xmm3
    vpermilpd %xmm12, %xmm8, %xmm7
    vpermilpd %xmm7, %xmm2, %xmm9
    vpermilpd %xmm9, %xmm6, %xmm12
    vpermilpd %xmm3, %xmm8, %xmm15
    vpermilpd %xmm15, %xmm11, %xmm9
    vpermilpd (%rax), %xmm14, %xmm3
    vpermilpd 8(%rsp), %xmm3, %xmm8
    vpermilpd -200(%rbp), %xmm8, %xmm7
    vpermilpd (%r12), %xmm7, %xmm11
    vpermilpd 0x40(%r13), %xmm11, %xmm1
    vpermilpd (%rax,%r9,8), %xmm1, %xmm14
    vpermilpd 16(%r15,%rcx,2), %xmm14, %xmm3
    vpermilpd -4(%rdx,%r14,4), %xmm3, %xmm8
    vpermilpd %ymm1, %ymm6, %ymm3
    vpermilpd %ymm12, %ymm0, %ymm7
    vpermilpd %ymm7, %ymm11, %ymm1
    vpermilpd %ymm9, %ymm14, %ymm3
    vpermilpd %ymm3, %ymm0, %ymm15
    vpermilpd %ymm15, %ymm2, %ymm9
    vpermilpd %ymm1, %ymm14, %ymm12
    vpermilpd %ymm12, %ymm8, %ymm15
    vpermilpd (%rax), %ymm14, %ymm3
    vpermilpd 8(%rsp), %ymm3, %ymm8
    vpermilpd -200(%rbp), %ymm8, %ymm7
    vpermilpd (%r12), %ymm7, %ymm11
    vpermilpd 0x40(%r13), %ymm11, %ymm1
    vpermilpd (%rax,%r9,8), %ymm1, %ymm14
    vpermilpd 16(%r15,%rcx,2), %ymm14, %ymm3
    vpermilpd -4(%rdx,%r14,4), %ymm3, %ymm8
    vpsrlvq %xmm7, %xmm2, %xmm1
    vpsrlvq %xmm9, %xmm6, %xmm3
    vpsrlvq %xmm3, %xmm8, %xmm7
    vpsrlvq %xmm15, %xmm11, %xmm1
    vpsrlvq %xmm1, %xmm6, %xmm12
    vpsrlvq %xmm12, %xmm0, %xmm15
    vpsrlvq %xmm7, %xmm11, %xmm9
    vpsrlvq %xmm9, %xmm14, %xmm12
    vpsrlvq (%rax), %xmm14, %xmm3
    vpsrlvq 8(%rsp), %xmm3, %xmm8
    vpsrlvq -200(%rbp), %xmm8, %xmm7
    vpsrlvq (%r12), %xmm7, %xmm11
    vpsrlvq 0x40(%r13), %xmm11, %xmm1
    vpsrlvq (%rax,%r9,8), %xmm1, %xmm14
    vpsrlvq 16(%r15,%rcx,2), %xmm14, %xmm3
    vpsrlvq -4(%rdx,%r14,4), %xmm3, %xmm8
    vpsrlvq %ymm3, %ymm0, %ymm7
    vpsrlvq %ymm15, %ymm2, %ymm1
    vpsrlvq %ymm1, %ymm14, %ymm3
    vpsrlvq %ymm12, %ymm8, %ymm7
    vpsrlvq %ymm7, %ymm2, %ymm9
    vpsrlvq %ymm9, %ymm6, %ymm12
    vpsrlvq %ymm3, %ymm8, %ymm15
    vpsrlvq %ymm15, %ymm11, %ymm9
    vpsrlvq (%rax), %ymm14, %ymm3
    vpsrlvq 8(%rsp), %ymm3, %ymm8
    vpsrlvq -200(%rbp), %ymm8, %ymm7
    vpsrlvq (%r12), %ymm7, %ymm11
    vpsrlvq 0x40(%r13), %ymm11, %ymm1
    vpsrlvq (%rax,%r9,8), %ymm1, %ymm14
    vpsrlvq 16(%r15,%rcx,2), %ymm14, %ymm3
    vpsrlvq -4(%rdx,%r14,4), %ymm3, %ymm8
    vpsllvq %xmm1, %xmm6, %xmm3
    vpsllvq %xmm12, %xmm0, %xmm7
    vpsllvq %xmm7, %xmm11, %xmm1
    vpsllvq %xmm9, %xmm14, %xmm3
    vpsllvq %xmm3, %xmm0, %xmm15
    vpsllvq %xmm15, %xmm2, %xmm9
    vpsllvq %xmm1, %xmm14, %xmm12
    vpsllvq %xmm12, %xmm8, %xmm15
    vpsllvq (%rax), %xmm14, %xmm3
    vpsllvq 8(%rsp), %xmm3, %xmm8
    vpsllvq -200(%rbp), %xmm8, %xmm7
    vpsllvq (%r12), %xmm7, %xmm11
    vpsllvq 0x40(%r13), %xmm11, %xmm1
    vpsllvq (%rax,%r9,8), %xmm1, %xmm14
    vpsllvq 16(%r15,%rcx,2), %xmm14, %xmm3
    vpsllvq -4(%rdx,%r14,4), %xmm3, %xmm8
    vpsllvq %ymm7, %ymm2, %ymm1
    vpsllvq %ymm9, %ymm6, %ymm3
    vpsllvq %ymm3, %ymm8, %ymm7
    vpsllvq %ymm15, %ymm11, %ymm1
    vpsllvq %ymm1, %ymm6, %ymm12
    vpsllvq %ymm12, %ymm0, %ymm15
    vpsllvq %ymm7, %ymm11, %ymm9
    vpsllvq %ymm9, %ymm14, %ymm12
    vpsllvq (%rax), %ymm14, %ymm3
    vpsllvq 8(%rsp), %ymm3, %ymm8
    vpsllvq -200(%rbp), %ymm8, %ymm7
    vpsllvq (%r12), %ymm7, %ymm11
    vpsllvq 0x40(%r13), %ymm11, %ymm1
    vpsllvq (%rax,%r9,8), %ymm1, %ymm14
    vpsllvq 16(%r15,%rcx,2), %ymm14, %ymm3
    vpsllvq -4(%rdx,%r14,4), %ymm3, %ymm8
    vpermd %ymm3, %ymm0, %ymm7
    vpermd %ymm15, %ymm2, %ymm1
    vpermd %ymm1, %ymm14, %ymm3
    vpermd %ymm12, %ymm8, %ymm7
    vpermd %ymm7, %ymm2, %ymm9
    vpermd %ymm9, %ymm6, %ymm12
    vpermd %ymm3, %ymm8, %ymm15
    vpermd %ymm15, %ymm11, %ymm9
    vpermd (%rax), %ymm14, %ymm3
    vpermd 8(%rsp), %ymm3, %ymm8
    vpermd -200(%rbp), %ymm8, %ymm7
    vpermd (%r12), %ymm7, %ymm11
    vpermd 0x40(%r13), %ymm11, %ymm1
    vpermd (%rax,%r9,8), %ymm1, %ymm14
    vpermd 16(%r15,%rcx,2), %ymm14, %ymm3
    vpermd -4(%rdx,%r14,4), %ymm3, %ymm8
    vpermps %ymm1, %ymm6, %ymm3
    vpermps %ymm12, %ymm0, %ymm7
    vpermps %ymm7, %ymm11, %ymm1
    vpermps %ymm9, %ymm14, %ymm3
    vpermps %ymm3, %ymm0, %ymm15
    vpermps %ymm15, %ymm2, %ymm9
    vpermps %ymm1, %ymm14, %ymm12
    vpermps %ymm12, %ymm8, %ymm15
    vpermps (%rax), %ymm14, %ymm3
    vpermps 8(%rsp), %ymm3, %ymm8
    vpermps -200(%rbp), %ymm8, %ymm7
    vpermps (%r12), %ymm7, %ymm11
    vpermps 0x40(%r13), %ymm11, %ymm1
    vpermps (%rax,%r9,8), %ymm1, %ymm14
    vpermps 16(%r15,%rcx,2), %ymm14, %ymm3
    vpermps -4(%rdx,%r14,4), %ymm3, %ymm8
    vpmovmskb %xmm7, %edx
    vpmovmskb %xmm9, %esi
    vpmovmskb %xmm3, %r8d
    vpmovmskb %xmm15, %r11d
    vpmovmskb %ymm3, %eax
    vpmovmskb %ymm15, %edx
    vpmovmskb %ymm1, %r14d
    vpmovmskb %ymm12, %r8d
    vmovmskps %xmm1, %esi
    vmovmskps %xmm12, %eax
    vmovmskps %xmm7, %r11d
    vmovmskps %xmm9, %r14d
    vmovmskps %ymm7, %edx
    vmovmskps %ymm9, %esi
    vmovmskps %ymm3, %r8d
    vmovmskps %ymm15, %r11d
    vmovmskpd %xmm3, %eax
    vmovmskpd %xmm15, %edx
    vmovmskpd %xmm1, %r14d
    vmovmskpd %xmm12, %r8d
    vmovmskpd %ymm1, %esi
    vmovmskpd %ymm12, %eax
    vmovmskpd %ymm7, %r11d
    vmovmskpd %ymm9, %r14d
    vsqrtps %xmm7, %xmm2
    vsqrtps %xmm9, %xmm6
    vsqrtps %xmm3, %xmm8
    vsqrtps %xmm15, %xmm11
    vsqrtps (%rax), %xmm14
    vsqrtps 8(%rsp), %xmm3
    vsqrtps -200(%rbp), %xmm8
    vsqrtps (%r12), %xmm7
    vsqrtps 0x40(%r13), %xmm11
    vsqrtps (%rax,%r9,8), %xmm1
    vsqrtps 16(%r15,%rcx,2), %xmm14
    vsqrtps -4(%rdx,%r14,4), %xmm3
    vsqrtps %ymm7, %ymm2
    vsqrtps %ymm9, %ymm6
    vsqrtps %ymm3, %ymm8
    vsqrtps %ymm15, %ymm11
    vsqrtps (%rax), %ymm14
    vsqrtps 8(%rsp), %ymm3
    vsqrtps -200(%rbp), %ymm8
    vsqrtps (%r12), %ymm7
    vsqrtps 0x40(%r13), %ymm11
    vsqrtps (%rax,%r9,8), %ymm1
    vsqrtps 16(%r15,%rcx,2), %ymm14
    vsqrtps -4(%rdx,%r14,4), %ymm3
    vsqrtpd %xmm7, %xmm2
    vsqrtpd %xmm9, %xmm6
    vsqrtpd %xmm3, %xmm8
    vsqrtpd %xmm15, %xmm11
    vsqrtpd (%rax), %xmm14
    vsqrtpd 8(%rsp), %xmm3
    vsqrtpd -200(%rbp), %xmm8
    vsqrtpd (%r12), %xmm7
    vsqrtpd 0x40(%r13), %xmm11
    vsqrtpd (%rax,%r9,8), %xmm1
    vsqrtpd 16(%r15,%rcx,2), %xmm14
    vsqrtpd -4(%rdx,%r14,4), %xmm3
    vsqrtpd %ymm7, %ymm2
    vsqrtpd %ymm9, %ymm6
    vsqrtpd %ymm3, %ymm8
    vsqrtpd %ymm15, %ymm11
    vsqrtpd (%rax), %ymm14
    vsqrtpd 8(%rsp), %ymm3
    vsqrtpd -200(%rbp), %ymm8
    vsqrtpd (%r12), %ymm7
    vsqrtpd 0x40(%r13), %ymm11
    vsqrtpd (%rax,%r9,8), %ymm1
    vsqrtpd 16(%r15,%rcx,2), %ymm14
    vsqrtpd -4(%rdx,%r14,4), %ymm3
    vcvtdq2ps %xmm7, %xmm2
    vcvtdq2ps %xmm9, %xmm6
    vcvtdq2ps %xmm3, %xmm8
    vcvtdq2ps %xmm15, %xmm11
    vcvtdq2ps (%rax), %xmm14
    vcvtdq2ps 8(%rsp), %xmm3
    vcvtdq2ps -200(%rbp), %xmm8
    vcvtdq2ps (%r12), %xmm7
    vcvtdq2ps 0x40(%r13), %xmm11
    vcvtdq2ps (%rax,%r9,8), %xmm1
    vcvtdq2ps 16(%r15,%rcx,2), %xmm14
    vcvtdq2ps -4(%rdx,%r14,4), %xmm3
    vcvtdq2ps %ymm7, %ymm2
    vcvtdq2ps %ymm9, %ymm6
    vcvtdq2ps %ymm3, %ymm8
    vcvtdq2ps %ymm15, %ymm11
    vcvtdq2ps (%rax), %ymm14
    vcvtdq2ps 8(%rsp), %ymm3
    vcvtdq2ps -200(%rbp), %ymm8
    vcvtdq2ps (%r12), %ymm7
    vcvtdq2ps 0x40(%r13), %ymm11
    vcvtdq2ps (%rax,%r9,8), %ymm1
    vcvtdq2ps 16(%r15,%rcx,2), %ymm14
    vcvtdq2ps -4(%rdx,%r14,4), %ymm3
    vcvttps2dq %xmm7, %xmm2
    vcvttps2dq %xmm9, %xmm6
    vcvttps2dq %xmm3, %xmm8
    vcvttps2dq %xmm15, %xmm11
    vcvttps2dq (%rax), %xmm14
    vcvttps2dq 8(%rsp), %xmm3
    vcvttps2dq -200(%rbp), %xmm8
    vcvttps2dq (%r12), %xmm7
    vcvttps2dq 0x40(%r13), %xmm11
    vcvttps2dq (%rax,%r9,8), %xmm1
    vcvttps2dq 16(%r15,%rcx,2), %xmm14
    vcvttps2dq -4(%rdx,%r14,4), %xmm3
    vcvttps2dq %ymm7, %ymm2
    vcvttps2dq %ymm9, %ymm6
    vcvttps2dq %ymm3, %ymm8
    vcvttps2dq %ymm15, %ymm11
    vcvttps2dq (%rax), %ymm14
    vcvttps2dq 8(%rsp), %ymm3
    vcvttps2dq -200(%rbp), %ymm8
    vcvttps2dq (%r12), %ymm7
    vcvttps2dq 0x40(%r13), %ymm11
    vcvttps2dq (%rax,%r9,8), %ymm1
    vcvttps2dq 16(%r15,%rcx,2), %ymm14
    vcvttps2dq -4(%rdx,%r14,4), %ymm3
    vcvtps2dq %xmm7, %xmm2
    vcvtps2dq %xmm9, %xmm6
    vcvtps2dq %xmm3, %xmm8
    vcvtps2dq %xmm15, %xmm11
    vcvtps2dq (%rax), %xmm14
    vcvtps2dq 8(%rsp), %xmm3
    vcvtps2dq -200(%rbp), %xmm8
    vcvtps2dq (%r12), %xmm7
    vcvtps2dq 0x40(%r13), %xmm11
    vcvtps2dq (%rax,%r9,8), %xmm1
    vcvtps2dq 16(%r15,%rcx,2), %xmm14
    vcvtps2dq -4(%rdx,%r14,4), %xmm3
    vcvtps2dq %ymm7, %ymm2
    vcvtps2dq %ymm9, %ymm6
    vcvtps2dq %ymm3, %ymm8
    vcvtps2dq %ymm15, %ymm11
    vcvtps2dq (%rax), %ymm14
    vcvtps2dq 8(%rsp), %ymm3
    vcvtps2dq -200(%rbp), %ymm8
    vcvtps2dq (%r12), %ymm7
    vcvtps2dq 0x40(%r13), %ymm11
    vcvtps2dq (%rax,%r9,8), %ymm1
    vcvtps2dq 16(%r15,%rcx,2), %ymm14
    vcvtps2dq -4(%rdx,%r14,4), %ymm3
    vpabsb %xmm7, %xmm2
    vpabsb %xmm9, %xmm6
    vpabsb %xmm3, %xmm8
    vpabsb %xmm15, %xmm11
    vpabsb (%rax), %xmm14
    vpabsb 8(%rsp), %xmm3
    vpabsb -200(%rbp), %xmm8
    vpabsb (%r12), %xmm7
    vpabsb 0x40(%r13), %xmm11
    vpabsb (%rax,%r9,8), %xmm1
    vpabsb 16(%r15,%rcx,2), %xmm14
    vpabsb -4(%rdx,%r14,4), %xmm3
    vpabsb %ymm7, %ymm2
    vpabsb %ymm9, %ymm6
    vpabsb %ymm3, %ymm8
    vpabsb %ymm15, %ymm11
    vpabsb (%rax), %ymm14
    vpabsb 8(%rsp), %ymm3
    vpabsb -200(%rbp), %ymm8
    vpabsb (%r12), %ymm7
    vpabsb 0x40(%r13), %ymm11
    vpabsb (%rax,%r9,8), %ymm1
    vpabsb 16(%r15,%rcx,2), %ymm14
    vpabsb -4(%rdx,%r14,4), %ymm3
    vpabsw %xmm7, %xmm2
    vpabsw %xmm9, %xmm6
    vpabsw %xmm3, %xmm8
    vpabsw %xmm15, %xmm11
    vpabsw (%rax), %xmm14
    vpabsw 8(%rsp), %xmm3
    vpabsw -200(%rbp), %xmm8
    vpabsw (%r12), %xmm7
    vpabsw 0x40(%r13), %xmm11
    vpabsw (%rax,%r9,8), %xmm1
    vpabsw 16(%r15,%rcx,2), %xmm14
    vpabsw -4(%rdx,%r14,4), %xmm3
    vpabsw %ymm7, %ymm2
    vpabsw %ymm9, %ymm6
    vpabsw %ymm3, %ymm8
    vpabsw %ymm15, %ymm11
    vpabsw (%rax), %ymm14
    vpabsw 8(%rsp), %ymm3
    vpabsw -200(%rbp), %ymm8
    vpabsw (%r12), %ymm7
    vpabsw 0x40(%r13), %ymm11
    vpabsw (%rax,%r9,8), %ymm1
    vpabsw 16(%r15,%rcx,2), %ymm14
    vpabsw -4(%rdx,%r14,4), %ymm3
    vpabsd %xmm7, %xmm2
    vpabsd %xmm9, %xmm6
    vpabsd %xmm3, %xmm8
    vpabsd %xmm15, %xmm11
    vpabsd (%rax), %xmm14
    vpabsd 8(%rsp), %xmm3
    vpabsd -200(%rbp), %xmm8
    vpabsd (%r12), %xmm7
    vpabsd 0x40(%r13), %xmm11
    vpabsd (%rax,%r9,8), %xmm1
    vpabsd 16(%r15,%rcx,2), %xmm14
    vpabsd -4(%rdx,%r14,4), %xmm3
    vpabsd %ymm7, %ymm2
    vpabsd %ymm9, %ymm6
    vpabsd %ymm3, %ymm8
    vpabsd %ymm15, %ymm11
    vpabsd (%rax), %ymm14
    vpabsd 8(%rsp), %ymm3
    vpabsd -200(%rbp), %ymm8
    vpabsd (%r12), %ymm7
    vpabsd 0x40(%r13), %ymm11
    vpabsd (%rax,%r9,8), %ymm1
    vpabsd 16(%r15,%rcx,2), %ymm14
    vpabsd -4(%rdx,%r14,4), %ymm3
    vptest %xmm7, %xmm2
    vptest %xmm9, %xmm6
    vptest %xmm3, %xmm8
    vptest %xmm15, %xmm11
    vptest (%rax), %xmm14
    vptest 8(%rsp), %xmm3
    vptest -200(%rbp), %xmm8
    vptest (%r12), %xmm7
    vptest 0x40(%r13), %xmm11
    vptest (%rax,%r9,8), %xmm1
    vptest 16(%r15,%rcx,2), %xmm14
    vptest -4(%rdx,%r14,4), %xmm3
    vptest %ymm7, %ymm2
    vptest %ymm9, %ymm6
    vptest %ymm3, %ymm8
    vptest %ymm15, %ymm11
    vptest (%rax), %ymm14
    vptest 8(%rsp), %ymm3
    vptest -200(%rbp), %ymm8
    vptest (%r12), %ymm7
    vptest 0x40(%r13), %ymm11
    vptest (%rax,%r9,8), %ymm1
    vptest 16(%r15,%rcx,2), %ymm14
    vptest -4(%rdx,%r14,4), %ymm3
    vtestps %xmm7, %xmm2
    vtestps %xmm9, %xmm6
    vtestps %xmm3, %xmm8
    vtestps %xmm15, %xmm11
    vtestps (%rax), %xmm14
    vtestps 8(%rsp), %xmm3
    vtestps -200(%rbp), %xmm8
    vtestps (%r12), %xmm7
    vtestps 0x40(%r13), %xmm11
    vtestps (%rax,%r9,8), %xmm1
    vtestps 16(%r15,%rcx,2), %xmm14
    vtestps -4(%rdx,%r14,4), %xmm3
    vtestps %ymm7, %ymm2
    vtestps %ymm9, %ymm6
    vtestps %ymm3, %ymm8
    vtestps %ymm15, %ymm11
    vtestps (%rax), %ymm14
    vtestps 8(%rsp), %ymm3
    vtestps -200(%rbp), %ymm8
    vtestps (%r12), %ymm7
    vtestps 0x40(%r13), %ymm11
    vtestps (%rax,%r9,8), %ymm1
    vtestps 16(%r15,%rcx,2), %ymm14
    vtestps -4(%rdx,%r14,4), %ymm3
    vtestpd %xmm7, %xmm2
    vtestpd %xmm9, %xmm6
    vtestpd %xmm3, %xmm8
    vtestpd %xmm15, %xmm11
    vtestpd (%rax), %xmm14
    vtestpd 8(%rsp), %xmm3
    vtestpd -200(%rbp), %xmm8
    vtestpd (%r12), %xmm7
    vtestpd 0x40(%r13), %xmm11
    vtestpd (%rax,%r9,8), %xmm1
    vtestpd 16(%r15,%rcx,2), %xmm14
    vtestpd -4(%rdx,%r14,4), %xmm3
    vtestpd %ymm7, %ymm2
    vtestpd %ymm9, %ymm6
    vtestpd %ymm3, %ymm8
    vtestpd %ymm15, %ymm11
    vtestpd (%rax), %ymm14
    vtestpd 8(%rsp), %ymm3
    vtestpd -200(%rbp), %ymm8
    vtestpd (%r12), %ymm7
    vtestpd 0x40(%r13), %ymm11
    vtestpd (%rax,%r9,8), %ymm1
    vtestpd 16(%r15,%rcx,2), %ymm14
    vtestpd -4(%rdx,%r14,4), %ymm3
    vpbroadcastb %xmm7, %xmm2
    vpbroadcastb %xmm9, %xmm6
    vpbroadcastb %xmm3, %xmm8
    vpbroadcastb %xmm15, %xmm11
    vpbroadcastb %xmm3, %ymm0
    vpbroadcastb %xmm15, %ymm2
    vpbroadcastb %xmm1, %ymm14
    vpbroadcastb %xmm12, %ymm8
    vpbroadcastw %xmm1, %xmm6
    vpbroadcastw %xmm12, %xmm0
    vpbroadcastw %xmm7, %xmm11
    vpbroadcastw %xmm9, %xmm14
    vpbroadcastw %xmm7, %ymm2
    vpbroadcastw %xmm9, %ymm6
    vpbroadcastw %xmm3, %ymm8
    vpbroadcastw %xmm15, %ymm11
    vpbroadcastd %xmm3, %xmm0
    vpbroadcastd %xmm15, %xmm2
    vpbroadcastd %xmm1, %xmm14
    vpbroadcastd %xmm12, %xmm8
    vpbroadcastd %xmm1, %ymm6
    vpbroadcastd %xmm12, %ymm0
    vpbroadcastd %xmm7, %ymm11
    vpbroadcastd %xmm9, %ymm14
    vpbroadcastq %xmm7, %xmm2
    vpbroadcastq %xmm9, %xmm6
    vpbroadcastq %xmm3, %xmm8
    vpbroadcastq %xmm15, %xmm11
    vpbroadcastq %xmm3, %ymm0
    vpbroadcastq %xmm15, %ymm2
    vpbroadcastq %xmm1, %ymm14
    vpbroadcastq %xmm12, %ymm8
    vbroadcastss %xmm1, %xmm6
    vbroadcastss %xmm12, %xmm0
    vbroadcastss %xmm7, %xmm11
    vbroadcastss %xmm9, %xmm14
    vbroadcastss %xmm7, %ymm2
    vbroadcastss %xmm9, %ymm6
    vbroadcastss %xmm3, %ymm8
    vbroadcastss %xmm15, %ymm11
    vbroadcastsd %xmm3, %ymm0
    vbroadcastsd %xmm15, %ymm2
    vbroadcastsd %xmm1, %ymm14
    vbroadcastsd %xmm12, %ymm8
    vmovshdup %xmm1, %xmm6
    vmovshdup %xmm12, %xmm0
    vmovshdup %xmm7, %xmm11
    vmovshdup %xmm9, %xmm14
    vmovshdup (%rax), %xmm14
    vmovshdup 8(%rsp), %xmm3
    vmovshdup -200(%rbp), %xmm8
    vmovshdup (%r12), %xmm7
    vmovshdup 0x40(%r13), %xmm11
    vmovshdup (%rax,%r9,8), %xmm1
    vmovshdup 16(%r15,%rcx,2), %xmm14
    vmovshdup -4(%rdx,%r14,4), %xmm3
    vmovshdup %ymm1, %ymm6
    vmovshdup %ymm12, %ymm0
    vmovshdup %ymm7, %ymm11
    vmovshdup %ymm9, %ymm14
    vmovshdup (%rax), %ymm14
    vmovshdup 8(%rsp), %ymm3
    vmovshdup -200(%rbp), %ymm8
    vmovshdup (%r12), %ymm7
    vmovshdup 0x40(%r13), %ymm11
    vmovshdup (%rax,%r9,8), %ymm1
    vmovshdup 16(%r15,%rcx,2), %ymm14
    vmovshdup -4(%rdx,%r14,4), %ymm3
    vmovsldup %xmm1, %xmm6
    vmovsldup %xmm12, %xmm0
    vmovsldup %xmm7, %xmm11
    vmovsldup %xmm9, %xmm14
    vmovsldup (%rax), %xmm14
    vmovsldup 8(%rsp), %xmm3
    vmovsldup -200(%rbp), %xmm8
    vmovsldup (%r12), %xmm7
    vmovsldup 0x40(%r13), %xmm11
    vmovsldup (%rax,%r9,8), %xmm1
    vmovsldup 16(%r15,%rcx,2), %xmm14
    vmovsldup -4(%rdx,%r14,4), %xmm3
    vmovsldup %ymm1, %ymm6
    vmovsldup %ymm12, %ymm0
    vmovsldup %ymm7, %ymm11
    vmovsldup %ymm9, %ymm14
    vmovsldup (%rax), %ymm14
    vmovsldup 8(%rsp), %ymm3
    vmovsldup -200(%rbp), %ymm8
    vmovsldup (%r12), %ymm7
    vmovsldup 0x40(%r13), %ymm11
    vmovsldup (%rax,%r9,8), %ymm1
    vmovsldup 16(%r15,%rcx,2), %ymm14
    vmovsldup -4(%rdx,%r14,4), %ymm3
    vpmovsxbw %xmm1, %ymm6
    vpmovsxbw %xmm12, %ymm0
    vpmovsxbw %xmm7, %ymm11
    vpmovsxbw %xmm9, %ymm14
    vpmovsxbw (%rax), %ymm14
    vpmovsxbw 8(%rsp), %ymm3
    vpmovsxbw -200(%rbp), %ymm8
    vpmovsxbw (%r12), %ymm7
    vpmovsxbw 0x40(%r13), %ymm11
    vpmovsxbw (%rax,%r9,8), %ymm1
    vpmovsxbw 16(%r15,%rcx,2), %ymm14
    vpmovsxbw -4(%rdx,%r14,4), %ymm3
    vpmovsxbd %xmm1, %ymm6
    vpmovsxbd %xmm12, %ymm0
    vpmovsxbd %xmm7, %ymm11
    vpmovsxbd %xmm9, %ymm14
    vpmovsxbd (%rax), %ymm14
    vpmovsxbd 8(%rsp), %ymm3
    vpmovsxbd -200(%rbp), %ymm8
    vpmovsxbd (%r12), %ymm7
    vpmovsxbd 0x40(%r13), %ymm11
    vpmovsxbd (%rax,%r9,8), %ymm1
    vpmovsxbd 16(%r15,%rcx,2), %ymm14
    vpmovsxbd -4(%rdx,%r14,4), %ymm3
    vpmovsxbq %xmm1, %ymm6
    vpmovsxbq %xmm12, %ymm0
    vpmovsxbq %xmm7, %ymm11
    vpmovsxbq %xmm9, %ymm14
    vpmovsxbq (%rax), %ymm14
    vpmovsxbq 8(%rsp), %ymm3
    vpmovsxbq -200(%rbp), %ymm8
    vpmovsxbq (%r12), %ymm7
    vpmovsxbq 0x40(%r13), %ymm11
    vpmovsxbq (%rax,%r9,8), %ymm1
    vpmovsxbq 16(%r15,%rcx,2), %ymm14
    vpmovsxbq -4(%rdx,%r14,4), %ymm3
    vpmovsxwd %xmm1, %ymm6
    vpmovsxwd %xmm12, %ymm0
    vpmovsxwd %xmm7, %ymm11
    vpmovsxwd %xmm9, %ymm14
    vpmovsxwd (%rax), %ymm14
    vpmovsxwd 8(%rsp), %ymm3
    vpmovsxwd -200(%rbp), %ymm8
    vpmovsxwd (%r12), %ymm7
    vpmovsxwd 0x40(%r13), %ymm11
    vpmovsxwd (%rax,%r9,8), %ymm1
    vpmovsxwd 16(%r15,%rcx,2), %ymm14
    vpmovsxwd -4(%rdx,%r14,4), %ymm3
    vpmovsxwq %xmm1, %ymm6
    vpmovsxwq %xmm12, %ymm0
    vpmovsxwq %xmm7, %ymm11
    vpmovsxwq %xmm9, %ymm14
    vpmovsxwq (%rax), %ymm14
    vpmovsxwq 8(%rsp), %ymm3
    vpmovsxwq -200(%rbp), %ymm8
    vpmovsxwq (%r12), %ymm7
    vpmovsxwq 0x40(%r13), %ymm11
    vpmovsxwq (%rax,%r9,8), %ymm1
    vpmovsxwq 16(%r15,%rcx,2), %ymm14
    vpmovsxwq -4(%rdx,%r14,4), %ymm3
    vpmovsxdq %xmm1, %ymm6
    vpmovsxdq %xmm12, %ymm0
    vpmovsxdq %xmm7, %ymm11
    vpmovsxdq %xmm9, %ymm14
    vpmovsxdq (%rax), %ymm14
    vpmovsxdq 8(%rsp), %ymm3
    vpmovsxdq -200(%rbp), %ymm8
    vpmovsxdq (%r12), %ymm7
    vpmovsxdq 0x40(%r13), %ymm11
    vpmovsxdq (%rax,%r9,8), %ymm1
    vpmovsxdq 16(%r15,%rcx,2), %ymm14
    vpmovsxdq -4(%rdx,%r14,4), %ymm3
    vpmovzxbw %xmm1, %ymm6
    vpmovzxbw %xmm12, %ymm0
    vpmovzxbw %xmm7, %ymm11
    vpmovzxbw %xmm9, %ymm14
    vpmovzxbw (%rax), %ymm14
    vpmovzxbw 8(%rsp), %ymm3
    vpmovzxbw -200(%rbp), %ymm8
    vpmovzxbw (%r12), %ymm7
    vpmovzxbw 0x40(%r13), %ymm11
    vpmovzxbw (%rax,%r9,8), %ymm1
    vpmovzxbw 16(%r15,%rcx,2), %ymm14
    vpmovzxbw -4(%rdx,%r14,4), %ymm3
    vpmovzxbd %xmm1, %ymm6
    vpmovzxbd %xmm12, %ymm0
    vpmovzxbd %xmm7, %ymm11
    vpmovzxbd %xmm9, %ymm14
    vpmovzxbd (%rax), %ymm14
    vpmovzxbd 8(%rsp), %ymm3
    vpmovzxbd -200(%rbp), %ymm8
    vpmovzxbd (%r12), %ymm7
    vpmovzxbd 0x40(%r13), %ymm11
    vpmovzxbd (%rax,%r9,8), %ymm1
    vpmovzxbd 16(%r15,%rcx,2), %ymm14
    vpmovzxbd -4(%rdx,%r14,4), %ymm3
    vpmovzxbq %xmm1, %ymm6
    vpmovzxbq %xmm12, %ymm0
    vpmovzxbq %xmm7, %ymm11
    vpmovzxbq %xmm9, %ymm14
    vpmovzxbq (%rax), %ymm14
    vpmovzxbq 8(%rsp), %ymm3
    vpmovzxbq -200(%rbp), %ymm8
    vpmovzxbq (%r12), %ymm7
    vpmovzxbq 0x40(%r13), %ymm11
    vpmovzxbq (%rax,%r9,8), %ymm1
    vpmovzxbq 16(%r15,%rcx,2), %ymm14
    vpmovzxbq -4(%rdx,%r14,4), %ymm3
    vpmovzxwd %xmm1, %ymm6
    vpmovzxwd %xmm12, %ymm0
    vpmovzxwd %xmm7, %ymm11
    vpmovzxwd %xmm9, %ymm14
    vpmovzxwd (%rax), %ymm14
    vpmovzxwd 8(%rsp), %ymm3
    vpmovzxwd -200(%rbp), %ymm8
    vpmovzxwd (%r12), %ymm7
    vpmovzxwd 0x40(%r13), %ymm11
    vpmovzxwd (%rax,%r9,8), %ymm1
    vpmovzxwd 16(%r15,%rcx,2), %ymm14
    vpmovzxwd -4(%rdx,%r14,4), %ymm3
    vpmovzxwq %xmm1, %ymm6
    vpmovzxwq %xmm12, %ymm0
    vpmovzxwq %xmm7, %ymm11
    vpmovzxwq %xmm9, %ymm14
    vpmovzxwq (%rax), %ymm14
    vpmovzxwq 8(%rsp), %ymm3
    vpmovzxwq -200(%rbp), %ymm8
    vpmovzxwq (%r12), %ymm7
    vpmovzxwq 0x40(%r13), %ymm11
    vpmovzxwq (%rax,%r9,8), %ymm1
    vpmovzxwq 16(%r15,%rcx,2), %ymm14
    vpmovzxwq -4(%rdx,%r14,4), %ymm3
    vpmovzxdq %xmm1, %ymm6
    vpmovzxdq %xmm12, %ymm0
    vpmovzxdq %xmm7, %ymm11
    vpmovzxdq %xmm9, %ymm14
    vpmovzxdq (%rax), %ymm14
    vpmovzxdq 8(%rsp), %ymm3
    vpmovzxdq -200(%rbp), %ymm8
    vpmovzxdq (%r12), %ymm7
    vpmovzxdq 0x40(%r13), %ymm11
    vpmovzxdq (%rax,%r9,8), %ymm1
    vpmovzxdq 16(%r15,%rcx,2), %ymm14
    vpmovzxdq -4(%rdx,%r14,4), %ymm3
    vpshufd $0, %xmm1, %xmm6
    vpshufd $0x7f, %xmm12, %xmm0
    vpshufd $0xff, %xmm7, %xmm11
    vpshufd $0, %xmm9, %xmm14
    vpshufd $0xff, (%rax), %xmm3
    vpshufd $0, 8(%rsp), %xmm8
    vpshufd $0x7f, -200(%rbp), %xmm7
    vpshufd $0xff, (%r12), %xmm11
    vpshufd $0, 0x40(%r13), %xmm1
    vpshufd $0x7f, (%rax,%r9,8), %xmm14
    vpshufd $0xff, 16(%r15,%rcx,2), %xmm3
    vpshufd $0, -4(%rdx,%r14,4), %xmm8
    vpshufd $0, %ymm1, %ymm6
    vpshufd $0x7f, %ymm12, %ymm0
    vpshufd $0xff, %ymm7, %ymm11
    vpshufd $0, %ymm9, %ymm14
    vpshufd $0xff, (%rax), %ymm3
    vpshufd $0, 8(%rsp), %ymm8
    vpshufd $0x7f, -200(%rbp), %ymm7
    vpshufd $0xff, (%r12), %ymm11
    vpshufd $0, 0x40(%r13), %ymm1
    vpshufd $0x7f, (%rax,%r9,8), %ymm14
    vpshufd $0xff, 16(%r15,%rcx,2), %ymm3
    vpshufd $0, -4(%rdx,%r14,4), %ymm8
    vpshuflw $0, %xmm1, %xmm6
    vpshuflw $0x7f, %xmm12, %xmm0
    vpshuflw $0xff, %xmm7, %xmm11
    vpshuflw $0, %xmm9, %xmm14
    vpshuflw $0xff, (%rax), %xmm3
    vpshuflw $0, 8(%rsp), %xmm8
    vpshuflw $0x7f, -200(%rbp), %xmm7
    vpshuflw $0xff, (%r12), %xmm11
    vpshuflw $0, 0x40(%r13), %xmm1
    vpshuflw $0x7f, (%rax,%r9,8), %xmm14
    vpshuflw $0xff, 16(%r15,%rcx,2), %xmm3
    vpshuflw $0, -4(%rdx,%r14,4), %xmm8
    vpshuflw $0, %ymm1, %ymm6
    vpshuflw $0x7f, %ymm12, %ymm0
    vpshuflw $0xff, %ymm7, %ymm11
    vpshuflw $0, %ymm9, %ymm14
    vpshuflw $0xff, (%rax), %ymm3
    vpshuflw $0, 8(%rsp), %ymm8
    vpshuflw $0x7f, -200(%rbp), %ymm7
    vpshuflw $0xff, (%r12), %ymm11
    vpshuflw $0, 0x40(%r13), %ymm1
    vpshuflw $0x7f, (%rax,%r9,8), %ymm14
    vpshuflw $0xff, 16(%r15,%rcx,2), %ymm3
    vpshuflw $0, -4(%rdx,%r14,4), %ymm8
    vpshufhw $0, %xmm1, %xmm6
    vpshufhw $0x7f, %xmm12, %xmm0
    vpshufhw $0xff, %xmm7, %xmm11
    vpshufhw $0, %xmm9, %xmm14
    vpshufhw $0xff, (%rax), %xmm3
    vpshufhw $0, 8(%rsp), %xmm8
    vpshufhw $0x7f, -200(%rbp), %xmm7
    vpshufhw $0xff, (%r12), %xmm11
    vpshufhw $0, 0x40(%r13), %xmm1
    vpshufhw $0x7f, (%rax,%r9,8), %xmm14
    vpshufhw $0xff, 16(%r15,%rcx,2), %xmm3
    vpshufhw $0, -4(%rdx,%r14,4), %xmm8
    vpshufhw $0, %ymm1, %ymm6
    vpshufhw $0x7f, %ymm12, %ymm0
    vpshufhw $0xff, %ymm7, %ymm11
    vpshufhw $0, %ymm9, %ymm14
    vpshufhw $0xff, (%rax), %ymm3
    vpshufhw $0, 8(%rsp), %ymm8
    vpshufhw $0x7f, -200(%rbp), %ymm7
    vpshufhw $0xff, (%r12), %ymm11
    vpshufhw $0, 0x40(%r13), %ymm1
    vpshufhw $0x7f, (%rax,%r9,8), %ymm14
    vpshufhw $0xff, 16(%r15,%rcx,2), %ymm3
    vpshufhw $0, -4(%rdx,%r14,4), %ymm8
    vpermq $0, %ymm1, %ymm6
    vpermq $0x7f, %ymm12, %ymm0
    vpermq $0xff, %ymm7, %ymm11
    vpermq $0, %ymm9, %ymm14
    vpermq $0xff, (%rax), %ymm3
    vpermq $0, 8(%rsp), %ymm8
    vpermq $0x7f, -200(%rbp), %ymm7
    vpermq $0xff, (%r12), %ymm11
    vpermq $0, 0x40(%r13), %ymm1
    vpermq $0x7f, (%rax,%r9,8), %ymm14
    vpermq $0xff, 16(%r15,%rcx,2), %ymm3
    vpermq $0, -4(%rdx,%r14,4), %ymm8
    vpermpd $0, %ymm1, %ymm6
    vpermpd $0x7f, %ymm12, %ymm0
    vpermpd $0xff, %ymm7, %ymm11
    vpermpd $0, %ymm9, %ymm14
    vpermpd $0xff, (%rax), %ymm3
    vpermpd $0, 8(%rsp), %ymm8
    vpermpd $0x7f, -200(%rbp), %ymm7
    vpermpd $0xff, (%r12), %ymm11
    vpermpd $0, 0x40(%r13), %ymm1
    vpermpd $0x7f, (%rax,%r9,8), %ymm14
    vpermpd $0xff, 16(%r15,%rcx,2), %ymm3
    vpermpd $0, -4(%rdx,%r14,4), %ymm8
    vroundps $0, %xmm1, %xmm6
    vroundps $0x7f, %xmm12, %xmm0
    vroundps $0xff, %xmm7, %xmm11
    vroundps $0, %xmm9, %xmm14
    vroundps $0xff, (%rax), %xmm3
    vroundps $0, 8(%rsp), %xmm8
    vroundps $0x7f, -200(%rbp), %xmm7
    vroundps $0xff, (%r12), %xmm11
    vroundps $0, 0x40(%r13), %xmm1
    vroundps $0x7f, (%rax,%r9,8), %xmm14
    vroundps $0xff, 16(%r15,%rcx,2), %xmm3
    vroundps $0, -4(%rdx,%r14,4), %xmm8
    vroundps $0, %ymm1, %ymm6
    vroundps $0x7f, %ymm12, %ymm0
    vroundps $0xff, %ymm7, %ymm11
    vroundps $0, %ymm9, %ymm14
    vroundps $0xff, (%rax), %ymm3
    vroundps $0, 8(%rsp), %ymm8
    vroundps $0x7f, -200(%rbp), %ymm7
    vroundps $0xff, (%r12), %ymm11
    vroundps $0, 0x40(%r13), %ymm1
    vroundps $0x7f, (%rax,%r9,8), %ymm14
    vroundps $0xff, 16(%r15,%rcx,2), %ymm3
    vroundps $0, -4(%rdx,%r14,4), %ymm8
    vroundpd $0, %xmm1, %xmm6
    vroundpd $0x7f, %xmm12, %xmm0
    vroundpd $0xff, %xmm7, %xmm11
    vroundpd $0, %xmm9, %xmm14
    vroundpd $0xff, (%rax), %xmm3
    vroundpd $0, 8(%rsp), %xmm8
    vroundpd $0x7f, -200(%rbp), %xmm7
    vroundpd $0xff, (%r12), %xmm11
    vroundpd $0, 0x40(%r13), %xmm1
    vroundpd $0x7f, (%rax,%r9,8), %xmm14
    vroundpd $0xff, 16(%r15,%rcx,2), %xmm3
    vroundpd $0, -4(%rdx,%r14,4), %xmm8
    vroundpd $0, %ymm1, %ymm6
    vroundpd $0x7f, %ymm12, %ymm0
    vroundpd $0xff, %ymm7, %ymm11
    vroundpd $0, %ymm9, %ymm14
    vroundpd $0xff, (%rax), %ymm3
    vroundpd $0, 8(%rsp), %ymm8
    vroundpd $0x7f, -200(%rbp), %ymm7
    vroundpd $0xff, (%r12), %ymm11
    vroundpd $0, 0x40(%r13), %ymm1
    vroundpd $0x7f, (%rax,%r9,8), %ymm14
    vroundpd $0xff, 16(%r15,%rcx,2), %ymm3
    vroundpd $0, -4(%rdx,%r14,4), %ymm8
    vextracti128 $0, %ymm1, %xmm6
    vextracti128 $0x7f, %ymm12, %xmm0
    vextracti128 $0xff, %ymm7, %xmm11
    vextracti128 $0, %ymm9, %xmm14
    vextracti128 $0xff, %ymm14, (%rax)
    vextracti128 $0, %ymm3, 8(%rsp)
    vextracti128 $0x7f, %ymm8, -200(%rbp)
    vextracti128 $0xff, %ymm7, (%r12)
    vextracti128 $0, %ymm11, 0x40(%r13)
    vextracti128 $0x7f, %ymm1, (%rax,%r9,8)
    vextracti128 $0xff, %ymm14, 16(%r15,%rcx,2)
    vextracti128 $0, %ymm3, -4(%rdx,%r14,4)
    vextractf128 $0, %ymm1, %xmm6
    vextractf128 $0x7f, %ymm12, %xmm0
    vextractf128 $0xff, %ymm7, %xmm11
    vextractf128 $0, %ymm9, %xmm14
    vextractf128 $0xff, %ymm14, (%rax)
    vextractf128 $0, %ymm3, 8(%rsp)
    vextractf128 $0x7f, %ymm8, -200(%rbp)
    vextractf128 $0xff, %ymm7, (%r12)
    vextractf128 $0, %ymm11, 0x40(%r13)
    vextractf128 $0x7f, %ymm1, (%rax,%r9,8)
    vextractf128 $0xff, %ymm14, 16(%r15,%rcx,2)
    vextractf128 $0, %ymm3, -4(%rdx,%r14,4)
    vpalignr $0, %xmm1, %xmm6, %xmm3
    vpalignr $0x7f, %xmm12, %xmm0, %xmm7
    vpalignr $0xff, %xmm7, %xmm11, %xmm1
    vpalignr $0, %xmm9, %xmm14, %xmm3
    vpalignr $0x7f, %xmm3, %xmm0, %xmm15
    vpalignr $0xff, %xmm15, %xmm2, %xmm9
    vpalignr $0, %xmm1, %xmm14, %xmm12
    vpalignr $0x7f, %xmm12, %xmm8, %xmm15
    vpalignr $0x7f, (%rax), %xmm3, %xmm8
    vpalignr $0xff, 8(%rsp), %xmm8, %xmm7
    vpalignr $0, -200(%rbp), %xmm7, %xmm11
    vpalignr $0x7f, (%r12), %xmm11, %xmm1
    vpalignr $0xff, 0x40(%r13), %xmm1, %xmm14
    vpalignr $0, (%rax,%r9,8), %xmm14, %xmm3
    vpalignr $0x7f, 16(%r15,%rcx,2), %xmm3, %xmm8
    vpalignr $0xff, -4(%rdx,%r14,4), %xmm8, %xmm7
    vpalignr $0xff, %ymm7, %ymm2, %ymm1
    vpalignr $0, %ymm9, %ymm6, %ymm3
    vpalignr $0x7f, %ymm3, %ymm8, %ymm7
    vpalignr $0xff, %ymm15, %ymm11, %ymm1
    vpalignr $0, %ymm1, %ymm6, %ymm12
    vpalignr $0x7f, %ymm12, %ymm0, %ymm15
    vpalignr $0xff, %ymm7, %ymm11, %ymm9
    vpalignr $0, %ymm9, %ymm14, %ymm12
    vpalignr $0, (%rax), %ymm3, %ymm8
    vpalignr $0x7f, 8(%rsp), %ymm8, %ymm7
    vpalignr $0xff, -200(%rbp), %ymm7, %ymm11
    vpalignr $0, (%r12), %ymm11, %ymm1
    vpalignr $0x7f, 0x40(%r13), %ymm1, %ymm14
    vpalignr $0xff, (%rax,%r9,8), %ymm14, %ymm3
    vpalignr $0, 16(%r15,%rcx,2), %ymm3, %ymm8
    vpalignr $0x7f, -4(%rdx,%r14,4), %ymm8, %ymm7
    vpblendw $0x7f, %xmm3, %xmm0, %xmm7
    vpblendw $0xff, %xmm15, %xmm2, %xmm1
    vpblendw $0, %xmm1, %xmm14, %xmm3
    vpblendw $0x7f, %xmm12, %xmm8, %xmm7
    vpblendw $0xff, %xmm7, %xmm2, %xmm9
    vpblendw $0, %xmm9, %xmm6, %xmm12
    vpblendw $0x7f, %xmm3, %xmm8, %xmm15
    vpblendw $0xff, %xmm15, %xmm11, %xmm9
    vpblendw $0xff, (%rax), %xmm3, %xmm8
    vpblendw $0, 8(%rsp), %xmm8, %xmm7
    vpblendw $0x7f, -200(%rbp), %xmm7, %xmm11
    vpblendw $0xff, (%r12), %xmm11, %xmm1
    vpblendw $0, 0x40(%r13), %xmm1, %xmm14
    vpblendw $0x7f, (%rax,%r9,8), %xmm14, %xmm3
    vpblendw $0xff, 16(%r15,%rcx,2), %xmm3, %xmm8
    vpblendw $0, -4(%rdx,%r14,4), %xmm8, %xmm7
    vpblendw $0, %ymm1, %ymm6, %ymm3
    vpblendw $0x7f, %ymm12, %ymm0, %ymm7
    vpblendw $0xff, %ymm7, %ymm11, %ymm1
    vpblendw $0, %ymm9, %ymm14, %ymm3
    vpblendw $0x7f, %ymm3, %ymm0, %ymm15
    vpblendw $0xff, %ymm15, %ymm2, %ymm9
    vpblendw $0, %ymm1, %ymm14, %ymm12
    vpblendw $0x7f, %ymm12, %ymm8, %ymm15
    vpblendw $0x7f, (%rax), %ymm3, %ymm8
    vpblendw $0xff, 8(%rsp), %ymm8, %ymm7
    vpblendw $0, -200(%rbp), %ymm7, %ymm11
    vpblendw $0x7f, (%r12), %ymm11, %ymm1
    vpblendw $0xff, 0x40(%r13), %ymm1, %ymm14
    vpblendw $0, (%rax,%r9,8), %ymm14, %ymm3
    vpblendw $0x7f, 16(%r15,%rcx,2), %ymm3, %ymm8
    vpblendw $0xff, -4(%rdx,%r14,4), %ymm8, %ymm7
    vpblendd $0xff, %xmm7, %xmm2, %xmm1
    vpblendd $0, %xmm9, %xmm6, %xmm3
    vpblendd $0x7f, %xmm3, %xmm8, %xmm7
    vpblendd $0xff, %xmm15, %xmm11, %xmm1
    vpblendd $0, %xmm1, %xmm6, %xmm12
    vpblendd $0x7f, %xmm12, %xmm0, %xmm15
    vpblendd $0xff, %xmm7, %xmm11, %xmm9
    vpblendd $0, %xmm9, %xmm14, %xmm12
    vpblendd $0, (%rax), %xmm3, %xmm8
    vpblendd $0x7f, 8(%rsp), %xmm8, %xmm7
    vpblendd $0xff, -200(%rbp), %xmm7, %xmm11
    vpblendd $0, (%r12), %xmm11, %xmm1
    vpblendd $0x7f, 0x40(%r13), %xmm1, %xmm14
    vpblendd $0xff, (%rax,%r9,8), %xmm14, %xmm3
    vpblendd $0, 16(%r15,%rcx,2), %xmm3, %xmm8
    vpblendd $0x7f, -4(%rdx,%r14,4), %xmm8, %xmm7
    vpblendd $0x7f, %ymm3, %ymm0, %ymm7
    vpblendd $0xff, %ymm15, %ymm2, %ymm1
    vpblendd $0, %ymm1, %ymm14, %ymm3
    vpblendd $0x7f, %ymm12, %ymm8, %ymm7
    vpblendd $0xff, %ymm7, %ymm2, %ymm9
    vpblendd $0, %ymm9, %ymm6, %ymm12
    vpblendd $0x7f, %ymm3, %ymm8, %ymm15
    vpblendd $0xff, %ymm15, %ymm11, %ymm9
    vpblendd $0xff, (%rax), %ymm3, %ymm8
    vpblendd $0, 8(%rsp), %ymm8, %ymm7
    vpblendd $0x7f, -200(%rbp), %ymm7, %ymm11
    vpblendd $0xff, (%r12), %ymm11, %ymm1
    vpblendd $0, 0x40(%r13), %ymm1, %ymm14
    vpblendd $0x7f, (%rax,%r9,8), %ymm14, %ymm3
    vpblendd $0xff, 16(%r15,%rcx,2), %ymm3, %ymm8
    vpblendd $0, -4(%rdx,%r14,4), %ymm8, %ymm7
    vblendps $0, %xmm1, %xmm6, %xmm3
    vblendps $0x7f, %xmm12, %xmm0, %xmm7
    vblendps $0xff, %xmm7, %xmm11, %xmm1
    vblendps $0, %xmm9, %xmm14, %xmm3
    vblendps $0x7f, %xmm3, %xmm0, %xmm15
    vblendps $0xff, %xmm15, %xmm2, %xmm9
    vblendps $0, %xmm1, %xmm14, %xmm12
    vblendps $0x7f, %xmm12, %xmm8, %xmm15
    vblendps $0x7f, (%rax), %xmm3, %xmm8
    vblendps $0xff, 8(%rsp), %xmm8, %xmm7
    vblendps $0, -200(%rbp), %xmm7, %xmm11
    vblendps $0x7f, (%r12), %xmm11, %xmm1
    vblendps $0xff, 0x40(%r13), %xmm1, %xmm14
    vblendps $0, (%rax,%r9,8), %xmm14, %xmm3
    vblendps $0x7f, 16(%r15,%rcx,2), %xmm3, %xmm8
    vblendps $0xff, -4(%rdx,%r14,4), %xmm8, %xmm7
    vblendps $0xff, %ymm7, %ymm2, %ymm1
    vblendps $0, %ymm9, %ymm6, %ymm3
    vblendps $0x7f, %ymm3, %ymm8, %ymm7
    vblendps $0xff, %ymm15, %ymm11, %ymm1
    vblendps $0, %ymm1, %ymm6, %ymm12
    vblendps $0x7f, %ymm12, %ymm0, %ymm15
    vblendps $0xff, %ymm7, %ymm11, %ymm9
    vblendps $0, %ymm9, %ymm14, %ymm12
    vblendps $0, (%rax), %ymm3, %ymm8
    vblendps $0x7f, 8(%rsp), %ymm8, %ymm7
    vblendps $0xff, -200(%rbp), %ymm7, %ymm11
    vblendps $0, (%r12), %ymm11, %ymm1
    vblendps $0x7f, 0x40(%r13), %ymm1, %ymm14
    vblendps $0xff, (%rax,%r9,8), %ymm14, %ymm3
    vblendps $0, 16(%r15,%rcx,2), %ymm3, %ymm8
    vblendps $0x7f, -4(%rdx,%r14,4), %ymm8, %ymm7
    vblendpd $0x7f, %xmm3, %xmm0, %xmm7
    vblendpd $0xff, %xmm15, %xmm2, %xmm1
    vblendpd $0, %xmm1, %xmm14, %xmm3
    vblendpd $0x7f, %xmm12, %xmm8, %xmm7
    vblendpd $0xff, %xmm7, %xmm2, %xmm9
    vblendpd $0, %xmm9, %xmm6, %xmm12
    vblendpd $0x7f, %xmm3, %xmm8, %xmm15
    vblendpd $0xff, %xmm15, %xmm11, %xmm9
    vblendpd $0xff, (%rax), %xmm3, %xmm8
    vblendpd $0, 8(%rsp), %xmm8, %xmm7
    vblendpd $0x7f, -200(%rbp), %xmm7, %xmm11
    vblendpd $0xff, (%r12), %xmm11, %xmm1
    vblendpd $0, 0x40(%r13), %xmm1, %xmm14
    vblendpd $0x7f, (%rax,%r9,8), %xmm14, %xmm3
    vblendpd $0xff, 16(%r15,%rcx,2), %xmm3, %xmm8
    vblendpd $0, -4(%rdx,%r14,4), %xmm8, %xmm7
    vblendpd $0, %ymm1, %ymm6, %ymm3
    vblendpd $0x7f, %ymm12, %ymm0, %ymm7
    vblendpd $0xff, %ymm7, %ymm11, %ymm1
    vblendpd $0, %ymm9, %ymm14, %ymm3
    vblendpd $0x7f, %ymm3, %ymm0, %ymm15
    vblendpd $0xff, %ymm15, %ymm2, %ymm9
    vblendpd $0, %ymm1, %ymm14, %ymm12
    vblendpd $0x7f, %ymm12, %ymm8, %ymm15
    vblendpd $0x7f, (%rax), %ymm3, %ymm8
    vblendpd $0xff, 8(%rsp), %ymm8, %ymm7
    vblendpd $0, -200(%rbp), %ymm7, %ymm11
    vblendpd $0x7f, (%r12), %ymm11, %ymm1
    vblendpd $0xff, 0x40(%r13), %ymm1, %ymm14
    vblendpd $0, (%rax,%r9,8), %ymm14, %ymm3
    vblendpd $0x7f, 16(%r15,%rcx,2), %ymm3, %ymm8
    vblendpd $0xff, -4(%rdx,%r14,4), %ymm8, %ymm7
    vshufps $0xff, %xmm7, %xmm2, %xmm1
    vshufps $0, %xmm9, %xmm6, %xmm3
    vshufps $0x7f, %xmm3, %xmm8, %xmm7
    vshufps $0xff, %xmm15, %xmm11, %xmm1
    vshufps $0, %xmm1, %xmm6, %xmm12
    vshufps $0x7f, %xmm12, %xmm0, %xmm15
    vshufps $0xff, %xmm7, %xmm11, %xmm9
    vshufps $0, %xmm9, %xmm14, %xmm12
    vshufps $0, (%rax), %xmm3, %xmm8
    vshufps $0x7f, 8(%rsp), %xmm8, %xmm7
    vshufps $0xff, -200(%rbp), %xmm7, %xmm11
    vshufps $0, (%r12), %xmm11, %xmm1
    vshufps $0x7f, 0x40(%r13), %xmm1, %xmm14
    vshufps $0xff, (%rax,%r9,8), %xmm14, %xmm3
    vshufps $0, 16(%r15,%rcx,2), %xmm3, %xmm8
    vshufps $0x7f, -4(%rdx,%r14,4), %xmm8, %xmm7
    vshufps $0x7f, %ymm3, %ymm0, %ymm7
    vshufps $0xff, %ymm15, %ymm2, %ymm1
    vshufps $0, %ymm1, %ymm14, %ymm3
    vshufps $0x7f, %ymm12, %ymm8, %ymm7
    vshufps $0xff, %ymm7, %ymm2, %ymm9
    vshufps $0, %ymm9, %ymm6, %ymm12
    vshufps $0x7f, %ymm3, %ymm8, %ymm15
    vshufps $0xff, %ymm15, %ymm11, %ymm9
    vshufps $0xff, (%rax), %ymm3, %ymm8
    vshufps $0, 8(%rsp), %ymm8, %ymm7
    vshufps $0x7f, -200(%rbp), %ymm7, %ymm11
    vshufps $0xff, (%r12), %ymm11, %ymm1
    vshufps $0, 0x40(%r13), %ymm1, %ymm14
    vshufps $0x7f, (%rax,%r9,8), %ymm14, %ymm3
    vshufps $0xff, 16(%r15,%rcx,2), %ymm3, %ymm8
    vshufps $0, -4(%rdx,%r14,4), %ymm8, %ymm7
    vshufpd $0, %xmm1, %xmm6, %xmm3
    vshufpd $0x7f, %xmm12, %xmm0, %xmm7
    vshufpd $0xff, %xmm7, %xmm11, %xmm1
    vshufpd $0, %xmm9, %xmm14, %xmm3
    vshufpd $0x7f, %xmm3, %xmm0, %xmm15
    vshufpd $0xff, %xmm15, %xmm2, %xmm9
    vshufpd $0, %xmm1, %xmm14, %xmm12
    vshufpd $0x7f, %xmm12, %xmm8, %xmm15
    vshufpd $0x7f, (%rax), %xmm3, %xmm8
    vshufpd $0xff, 8(%rsp), %xmm8, %xmm7
    vshufpd $0, -200(%rbp), %xmm7, %xmm11
    vshufpd $0x7f, (%r12), %xmm11, %xmm1
    vshufpd $0xff, 0x40(%r13), %xmm1, %xmm14
    vshufpd $0, (%rax,%r9,8), %xmm14, %xmm3
    vshufpd $0x7f, 16(%r15,%rcx,2), %xmm3, %xmm8
    vshufpd $0xff, -4(%rdx,%r14,4), %xmm8, %xmm7
    vshufpd $0xff, %ymm7, %ymm2, %ymm1
    vshufpd $0, %ymm9, %ymm6, %ymm3
    vshufpd $0x7f, %ymm3, %ymm8, %ymm7
    vshufpd $0xff, %ymm15, %ymm11, %ymm1
    vshufpd $0, %ymm1, %ymm6, %ymm12
    vshufpd $0x7f, %ymm12, %ymm0, %ymm15
    vshufpd $0xff, %ymm7, %ymm11, %ymm9
    vshufpd $0, %ymm9, %ymm14, %ymm12
    vshufpd $0, (%rax), %ymm3, %ymm8
    vshufpd $0x7f, 8(%rsp), %ymm8, %ymm7
    vshufpd $0xff, -200(%rbp), %ymm7, %ymm11
    vshufpd $0, (%r12), %ymm11, %ymm1
    vshufpd $0x7f, 0x40(%r13), %ymm1, %ymm14
    vshufpd $0xff, (%rax,%r9,8), %ymm14, %ymm3
    vshufpd $0, 16(%r15,%rcx,2), %ymm3, %ymm8
    vshufpd $0x7f, -4(%rdx,%r14,4), %ymm8, %ymm7
    vcmpps $0x7f, %xmm3, %xmm0, %xmm7
    vcmpps $0xff, %xmm15, %xmm2, %xmm1
    vcmpps $0, %xmm1, %xmm14, %xmm3
    vcmpps $0x7f, %xmm12, %xmm8, %xmm7
    vcmpps $0xff, %xmm7, %xmm2, %xmm9
    vcmpps $0, %xmm9, %xmm6, %xmm12
    vcmpps $0x7f, %xmm3, %xmm8, %xmm15
    vcmpps $0xff, %xmm15, %xmm11, %xmm9
    vcmpps $0xff, (%rax), %xmm3, %xmm8
    vcmpps $0, 8(%rsp), %xmm8, %xmm7
    vcmpps $0x7f, -200(%rbp), %xmm7, %xmm11
    vcmpps $0xff, (%r12), %xmm11, %xmm1
    vcmpps $0, 0x40(%r13), %xmm1, %xmm14
    vcmpps $0x7f, (%rax,%r9,8), %xmm14, %xmm3
    vcmpps $0xff, 16(%r15,%rcx,2), %xmm3, %xmm8
    vcmpps $0, -4(%rdx,%r14,4), %xmm8, %xmm7
    vcmpps $0, %ymm1, %ymm6, %ymm3
    vcmpps $0x7f, %ymm12, %ymm0, %ymm7
    vcmpps $0xff, %ymm7, %ymm11, %ymm1
    vcmpps $0, %ymm9, %ymm14, %ymm3
    vcmpps $0x7f, %ymm3, %ymm0, %ymm15
    vcmpps $0xff, %ymm15, %ymm2, %ymm9
    vcmpps $0, %ymm1, %ymm14, %ymm12
    vcmpps $0x7f, %ymm12, %ymm8, %ymm15
    vcmpps $0x7f, (%rax), %ymm3, %ymm8
    vcmpps $0xff, 8(%rsp), %ymm8, %ymm7
    vcmpps $0, -200(%rbp), %ymm7, %ymm11
    vcmpps $0x7f, (%r12), %ymm11, %ymm1
    vcmpps $0xff, 0x40(%r13), %ymm1, %ymm14
    vcmpps $0, (%rax,%r9,8), %ymm14, %ymm3
    vcmpps $0x7f, 16(%r15,%rcx,2), %ymm3, %ymm8
    vcmpps $0xff, -4(%rdx,%r14,4), %ymm8, %ymm7
    vcmppd $0xff, %xmm7, %xmm2, %xmm1
    vcmppd $0, %xmm9, %xmm6, %xmm3
    vcmppd $0x7f, %xmm3, %xmm8, %xmm7
    vcmppd $0xff, %xmm15, %xmm11, %xmm1
    vcmppd $0, %xmm1, %xmm6, %xmm12
    vcmppd $0x7f, %xmm12, %xmm0, %xmm15
    vcmppd $0xff, %xmm7, %xmm11, %xmm9
    vcmppd $0, %xmm9, %xmm14, %xmm12
    vcmppd $0, (%rax), %xmm3, %xmm8
    vcmppd $0x7f, 8(%rsp), %xmm8, %xmm7
    vcmppd $0xff, -200(%rbp), %xmm7, %xmm11
    vcmppd $0, (%r12), %xmm11, %xmm1
    vcmppd $0x7f, 0x40(%r13), %xmm1, %xmm14
    vcmppd $0xff, (%rax,%r9,8), %xmm14, %xmm3
    vcmppd $0, 16(%r15,%rcx,2), %xmm3, %xmm8
    vcmppd $0x7f, -4(%rdx,%r14,4), %xmm8, %xmm7
    vcmppd $0x7f, %ymm3, %ymm0, %ymm7
    vcmppd $0xff, %ymm15, %ymm2, %ymm1
    vcmppd $0, %ymm1, %ymm14, %ymm3
    vcmppd $0x7f, %ymm12, %ymm8, %ymm7
    vcmppd $0xff, %ymm7, %ymm2, %ymm9
    vcmppd $0, %ymm9, %ymm6, %ymm12
    vcmppd $0x7f, %ymm3, %ymm8, %ymm15
    vcmppd $0xff, %ymm15, %ymm11, %ymm9
    vcmppd $0xff, (%rax), %ymm3, %ymm8
    vcmppd $0, 8(%rsp), %ymm8, %ymm7
    vcmppd $0x7f, -200(%rbp), %ymm7, %ymm11
    vcmppd $0xff, (%r12), %ymm11, %ymm1
    vcmppd $0, 0x40(%r13), %ymm1, %ymm14
    vcmppd $0x7f, (%rax,%r9,8), %ymm14, %ymm3
    vcmppd $0xff, 16(%r15,%rcx,2), %ymm3, %ymm8
    vcmppd $0, -4(%rdx,%r14,4), %ymm8, %ymm7
    vperm2i128 $0, %ymm1, %ymm6, %ymm3
    vperm2i128 $0x7f, %ymm12, %ymm0, %ymm7
    vperm2i128 $0xff, %ymm7, %ymm11, %ymm1
    vperm2i128 $0, %ymm9, %ymm14, %ymm3
    vperm2i128 $0x7f, %ymm3, %ymm0, %ymm15
    vperm2i128 $0xff, %ymm15, %ymm2, %ymm9
    vperm2i128 $0, %ymm1, %ymm14, %ymm12
    vperm2i128 $0x7f, %ymm12, %ymm8, %ymm15
    vperm2i128 $0x7f, (%rax), %ymm3, %ymm8
    vperm2i128 $0xff, 8(%rsp), %ymm8, %ymm7
    vperm2i128 $0, -200(%rbp), %ymm7, %ymm11
    vperm2i128 $0x7f, (%r12), %ymm11, %ymm1
    vperm2i128 $0xff, 0x40(%r13), %ymm1, %ymm14
    vperm2i128 $0, (%rax,%r9,8), %ymm14, %ymm3
    vperm2i128 $0x7f, 16(%r15,%rcx,2), %ymm3, %ymm8
    vperm2i128 $0xff, -4(%rdx,%r14,4), %ymm8, %ymm7
    vperm2f128 $0xff, %ymm7, %ymm2, %ymm1
    vperm2f128 $0, %ymm9, %ymm6, %ymm3
    vperm2f128 $0x7f, %ymm3, %ymm8, %ymm7
    vperm2f128 $0xff, %ymm15, %ymm11, %ymm1
    vperm2f128 $0, %ymm1, %ymm6, %ymm12
    vperm2f128 $0x7f, %ymm12, %ymm0, %ymm15
    vperm2f128 $0xff, %ymm7, %ymm11, %ymm9
    vperm2f128 $0, %ymm9, %ymm14, %ymm12
    vperm2f128 $0, (%rax), %ymm3, %ymm8
    vperm2f128 $0x7f, 8(%rsp), %ymm8, %ymm7
    vperm2f128 $0xff, -200(%rbp), %ymm7, %ymm11
    vperm2f128 $0, (%r12), %ymm11, %ymm1
    vperm2f128 $0x7f, 0x40(%r13), %ymm1, %ymm14
    vperm2f128 $0xff, (%rax,%r9,8), %ymm14, %ymm3
    vperm2f128 $0, 16(%r15,%rcx,2), %ymm3, %ymm8
    vperm2f128 $0x7f, -4(%rdx,%r14,4), %ymm8, %ymm7
    vinserti128 $0x7f, %xmm3, %ymm0, %ymm7
    vinserti128 $0xff, %xmm15, %ymm2, %ymm1
    vinserti128 $0, %xmm1, %ymm14, %ymm3
    vinserti128 $0x7f, %xmm12, %ymm8, %ymm7
    vinserti128 $0xff, %xmm7, %ymm2, %ymm9
    vinserti128 $0, %xmm9, %ymm6, %ymm12
    vinserti128 $0x7f, %xmm3, %ymm8, %ymm15
    vinserti128 $0xff, %xmm15, %ymm11, %ymm9
    vinserti128 $0xff, (%rax), %ymm3, %ymm8
    vinserti128 $0, 8(%rsp), %ymm8, %ymm7
    vinserti128 $0x7f, -200(%rbp), %ymm7, %ymm11
    vinserti128 $0xff, (%r12), %ymm11, %ymm1
    vinserti128 $0, 0x40(%r13), %ymm1, %ymm14
    vinserti128 $0x7f, (%rax,%r9,8), %ymm14, %ymm3
    vinserti128 $0xff, 16(%r15,%rcx,2), %ymm3, %ymm8
    vinserti128 $0, -4(%rdx,%r14,4), %ymm8, %ymm7
    vinsertf128 $0, %xmm1, %ymm6, %ymm3
    vinsertf128 $0x7f, %xmm12, %ymm0, %ymm7
    vinsertf128 $0xff, %xmm7, %ymm11, %ymm1
    vinsertf128 $0, %xmm9, %ymm14, %ymm3
    vinsertf128 $0x7f, %xmm3, %ymm0, %ymm15
    vinsertf128 $0xff, %xmm15, %ymm2, %ymm9
    vinsertf128 $0, %xmm1, %ymm14, %ymm12
    vinsertf128 $0x7f, %xmm12, %ymm8, %ymm15
    vinsertf128 $0x7f, (%rax), %ymm3, %ymm8
    vinsertf128 $0xff, 8(%rsp), %ymm8, %ymm7
    vinsertf128 $0, -200(%rbp), %ymm7, %ymm11
    vinsertf128 $0x7f, (%r12), %ymm11, %ymm1
    vinsertf128 $0xff, 0x40(%r13), %ymm1, %ymm14
    vinsertf128 $0, (%rax,%r9,8), %ymm14, %ymm3
    vinsertf128 $0x7f, 16(%r15,%rcx,2), %ymm3, %ymm8
    vinsertf128 $0xff, -4(%rdx,%r14,4), %ymm8, %ymm7
    vpblendvb %xmm7, %xmm2, %xmm1, %xmm6
    vpblendvb %xmm9, %xmm6, %xmm3, %xmm0
    vpblendvb %xmm3, %xmm8, %xmm7, %xmm2
    vpblendvb %xmm15, %xmm11, %xmm1, %xmm6
    vpblendvb %xmm1, %xmm6, %xmm12, %xmm0
    vpblendvb %xmm12, %xmm0, %xmm15, %xmm2
    vpblendvb %xmm7, %xmm11, %xmm9, %xmm6
    vpblendvb %xmm9, %xmm14, %xmm12, %xmm0
    vpblendvb %xmm3, %xmm0, %xmm7, %xmm11
    vpblendvb %xmm15, %xmm2, %xmm1, %xmm14
    vpblendvb %xmm1, %xmm14, %xmm3, %xmm8
    vpblendvb %xmm12, %xmm8, %xmm7, %xmm11
    vpblendvb %xmm7, %xmm2, %xmm9, %xmm14
    vpblendvb %xmm9, %xmm6, %xmm12, %xmm8
    vpblendvb %xmm3, %xmm8, %xmm15, %xmm11
    vpblendvb %xmm15, %xmm11, %xmm9, %xmm14
    vpblendvb %xmm1, (%rax), %xmm3, %xmm8
    vpblendvb %xmm14, 8(%rsp), %xmm8, %xmm7
    vpblendvb %xmm3, -200(%rbp), %xmm7, %xmm11
    vpblendvb %xmm8, (%r12), %xmm11, %xmm1
    vpblendvb %xmm7, 0x40(%r13), %xmm1, %xmm14
    vpblendvb %xmm11, (%rax,%r9,8), %xmm14, %xmm3
    vpblendvb %xmm1, 16(%r15,%rcx,2), %xmm3, %xmm8
    vpblendvb %xmm14, -4(%rdx,%r14,4), %xmm8, %xmm7
    vpblendvb %ymm7, %ymm2, %ymm1, %ymm6
    vpblendvb %ymm9, %ymm6, %ymm3, %ymm0
    vpblendvb %ymm3, %ymm8, %ymm7, %ymm2
    vpblendvb %ymm15, %ymm11, %ymm1, %ymm6
    vpblendvb %ymm1, %ymm6, %ymm12, %ymm0
    vpblendvb %ymm12, %ymm0, %ymm15, %ymm2
    vpblendvb %ymm7, %ymm11, %ymm9, %ymm6
    vpblendvb %ymm9, %ymm14, %ymm12, %ymm0
    vpblendvb %ymm3, %ymm0, %ymm7, %ymm11
    vpblendvb %ymm15, %ymm2, %ymm1, %ymm14
    vpblendvb %ymm1, %ymm14, %ymm3, %ymm8
    vpblendvb %ymm12, %ymm8, %ymm7, %ymm11
    vpblendvb %ymm7, %ymm2, %ymm9, %ymm14
    vpblendvb %ymm9, %ymm6, %ymm12, %ymm8
    vpblendvb %ymm3, %ymm8, %ymm15, %ymm11
    vpblendvb %ymm15, %ymm11, %ymm9, %ymm14
    vpblendvb %ymm1, (%rax), %ymm3, %ymm8
    vpblendvb %ymm14, 8(%rsp), %ymm8, %ymm7
    vpblendvb %ymm3, -200(%rbp), %ymm7, %ymm11
    vpblendvb %ymm8, (%r12), %ymm11, %ymm1
    vpblendvb %ymm7, 0x40(%r13), %ymm1, %ymm14
    vpblendvb %ymm11, (%rax,%r9,8), %ymm14, %ymm3
    vpblendvb %ymm1, 16(%r15,%rcx,2), %ymm3, %ymm8
    vpblendvb %ymm14, -4(%rdx,%r14,4), %ymm8, %ymm7
    vblendvps %xmm7, %xmm2, %xmm1, %xmm6
    vblendvps %xmm9, %xmm6, %xmm3, %xmm0
    vblendvps %xmm3, %xmm8, %xmm7, %xmm2
    vblendvps %xmm15, %xmm11, %xmm1, %xmm6
    vblendvps %xmm1, %xmm6, %xmm12, %xmm0
    vblendvps %xmm12, %xmm0, %xmm15, %xmm2
    vblendvps %xmm7, %xmm11, %xmm9, %xmm6
    vblendvps %xmm9, %xmm14, %xmm12, %xmm0
    vblendvps %xmm3, %xmm0, %xmm7, %xmm11
    vblendvps %xmm15, %xmm2, %xmm1, %xmm14
    vblendvps %xmm1, %xmm14, %xmm3, %xmm8
    vblendvps %xmm12, %xmm8, %xmm7, %xmm11
    vblendvps %xmm7, %xmm2, %xmm9, %xmm14
    vblendvps %xmm9, %xmm6, %xmm12, %xmm8
    vblendvps %xmm3, %xmm8, %xmm15, %xmm11
    vblendvps %xmm15, %xmm11, %xmm9, %xmm14
    vblendvps %xmm1, (%rax), %xmm3, %xmm8
    vblendvps %xmm14, 8(%rsp), %xmm8, %xmm7
    vblendvps %xmm3, -200(%rbp), %xmm7, %xmm11
    vblendvps %xmm8, (%r12), %xmm11, %xmm1
    vblendvps %xmm7, 0x40(%r13), %xmm1, %xmm14
    vblendvps %xmm11, (%rax,%r9,8), %xmm14, %xmm3
    vblendvps %xmm1, 16(%r15,%rcx,2), %xmm3, %xmm8
    vblendvps %xmm14, -4(%rdx,%r14,4), %xmm8, %xmm7
    vblendvps %ymm7, %ymm2, %ymm1, %ymm6
    vblendvps %ymm9, %ymm6, %ymm3, %ymm0
    vblendvps %ymm3, %ymm8, %ymm7, %ymm2
    vblendvps %ymm15, %ymm11, %ymm1, %ymm6
    vblendvps %ymm1, %ymm6, %ymm12, %ymm0
    vblendvps %ymm12, %ymm0, %ymm15, %ymm2
    vblendvps %ymm7, %ymm11, %ymm9, %ymm6
    vblendvps %ymm9, %ymm14, %ymm12, %ymm0
    vblendvps %ymm3, %ymm0, %ymm7, %ymm11
    vblendvps %ymm15, %ymm2, %ymm1, %ymm14
    vblendvps %ymm1, %ymm14, %ymm3, %ymm8
    vblendvps %ymm12, %ymm8, %ymm7, %ymm11
    vblendvps %ymm7, %ymm2, %ymm9, %ymm14
    vblendvps %ymm9, %ymm6, %ymm12, %ymm8
    vblendvps %ymm3, %ymm8, %ymm15, %ymm11
    vblendvps %ymm15, %ymm11, %ymm9, %ymm14
    vblendvps %ymm1, (%rax), %ymm3, %ymm8
    vblendvps %ymm14, 8(%rsp), %ymm8, %ymm7
    vblendvps %ymm3, -200(%rbp), %ymm7, %ymm11
    vblendvps %ymm8, (%r12), %ymm11, %ymm1
    vblendvps %ymm7, 0x40(%r13), %ymm1, %ymm14
    vblendvps %ymm11, (%rax,%r9,8), %ymm14, %ymm3
    vblendvps %ymm1, 16(%r15,%rcx,2), %ymm3, %ymm8
    vblendvps %ymm14, -4(%rdx,%r14,4), %ymm8, %ymm7
    vblendvpd %xmm7, %xmm2, %xmm1, %xmm6
    vblendvpd %xmm9, %xmm6, %xmm3, %xmm0
    vblendvpd %xmm3, %xmm8, %xmm7, %xmm2
    vblendvpd %xmm15, %xmm11, %xmm1, %xmm6
    vblendvpd %xmm1, %xmm6, %xmm12, %xmm0
    vblendvpd %xmm12, %xmm0, %xmm15, %xmm2
    vblendvpd %xmm7, %xmm11, %xmm9, %xmm6
    vblendvpd %xmm9, %xmm14, %xmm12, %xmm0
    vblendvpd %xmm3, %xmm0, %xmm7, %xmm11
    vblendvpd %xmm15, %xmm2, %xmm1, %xmm14
    vblendvpd %xmm1, %xmm14, %xmm3, %xmm8
    vblendvpd %xmm12, %xmm8, %xmm7, %xmm11
    vblendvpd %xmm7, %xmm2, %xmm9, %xmm14
    vblendvpd %xmm9, %xmm6, %xmm12, %xmm8
    vblendvpd %xmm3, %xmm8, %xmm15, %xmm11
    vblendvpd %xmm15, %xmm11, %xmm9, %xmm14
    vblendvpd %xmm1, (%rax), %xmm3, %xmm8
    vblendvpd %xmm14, 8(%rsp), %xmm8, %xmm7
    vblendvpd %xmm3, -200(%rbp), %xmm7, %xmm11
    vblendvpd %xmm8, (%r12), %xmm11, %xmm1
    vblendvpd %xmm7, 0x40(%r13), %xmm1, %xmm14
    vblendvpd %xmm11, (%rax,%r9,8), %xmm14, %xmm3
    vblendvpd %xmm1, 16(%r15,%rcx,2), %xmm3, %xmm8
    vblendvpd %xmm14, -4(%rdx,%r14,4), %xmm8, %xmm7
    vblendvpd %ymm7, %ymm2, %ymm1, %ymm6
    vblendvpd %ymm9, %ymm6, %ymm3, %ymm0
    vblendvpd %ymm3, %ymm8, %ymm7, %ymm2
    vblendvpd %ymm15, %ymm11, %ymm1, %ymm6
    vblendvpd %ymm1, %ymm6, %ymm12, %ymm0
    vblendvpd %ymm12, %ymm0, %ymm15, %ymm2
    vblendvpd %ymm7, %ymm11, %ymm9, %ymm6
    vblendvpd %ymm9, %ymm14, %ymm12, %ymm0
    vblendvpd %ymm3, %ymm0, %ymm7, %ymm11
    vblendvpd %ymm15, %ymm2, %ymm1, %ymm14
    vblendvpd %ymm1, %ymm14, %ymm3, %ymm8
    vblendvpd %ymm12, %ymm8, %ymm7, %ymm11
    vblendvpd %ymm7, %ymm2, %ymm9, %ymm14
    vblendvpd %ymm9, %ymm6, %ymm12, %ymm8
    vblendvpd %ymm3, %ymm8, %ymm15, %ymm11
    vblendvpd %ymm15, %ymm11, %ymm9, %ymm14
    vblendvpd %ymm1, (%rax), %ymm3, %ymm8
    vblendvpd %ymm14, 8(%rsp), %ymm8, %ymm7
    vblendvpd %ymm3, -200(%rbp), %ymm7, %ymm11
    vblendvpd %ymm8, (%r12), %ymm11, %ymm1
    vblendvpd %ymm7, 0x40(%r13), %ymm1, %ymm14
    vblendvpd %ymm11, (%rax,%r9,8), %ymm14, %ymm3
    vblendvpd %ymm1, 16(%r15,%rcx,2), %ymm3, %ymm8
    vblendvpd %ymm14, -4(%rdx,%r14,4), %ymm8, %ymm7
    vpsllw $0xff, %xmm7, %xmm2
    vpsllw $0, %xmm9, %xmm6
    vpsllw $0x7f, %xmm3, %xmm8
    vpsllw $0xff, %xmm15, %xmm11
    vpsllw $0x7f, %ymm3, %ymm0
    vpsllw $0xff, %ymm15, %ymm2
    vpsllw $0, %ymm1, %ymm14
    vpsllw $0x7f, %ymm12, %ymm8
    vpsllw %xmm1, %xmm6, %xmm3
    vpsllw %xmm12, %xmm0, %xmm7
    vpsllw %xmm7, %xmm11, %xmm1
    vpsllw %xmm9, %xmm14, %xmm3
    vpsllw %xmm3, %xmm0, %xmm15
    vpsllw %xmm15, %xmm2, %xmm9
    vpsllw %xmm1, %xmm14, %xmm12
    vpsllw %xmm12, %xmm8, %xmm15
    vpsllw (%rax), %xmm14, %xmm3
    vpsllw 8(%rsp), %xmm3, %xmm8
    vpsllw -200(%rbp), %xmm8, %xmm7
    vpsllw (%r12), %xmm7, %xmm11
    vpsllw 0x40(%r13), %xmm11, %xmm1
    vpsllw (%rax,%r9,8), %xmm1, %xmm14
    vpsllw 16(%r15,%rcx,2), %xmm14, %xmm3
    vpsllw -4(%rdx,%r14,4), %xmm3, %xmm8
    vpsllw %xmm7, %ymm2, %ymm1
    vpsllw %xmm9, %ymm6, %ymm3
    vpsllw %xmm3, %ymm8, %ymm7
    vpsllw %xmm15, %ymm11, %ymm1
    vpsllw %xmm1, %ymm6, %ymm12
    vpsllw %xmm12, %ymm0, %ymm15
    vpsllw %xmm7, %ymm11, %ymm9
    vpsllw %xmm9, %ymm14, %ymm12
    vpsllw (%rax), %ymm14, %ymm3
    vpsllw 8(%rsp), %ymm3, %ymm8
    vpsllw -200(%rbp), %ymm8, %ymm7
    vpsllw (%r12), %ymm7, %ymm11
    vpsllw 0x40(%r13), %ymm11, %ymm1
    vpsllw (%rax,%r9,8), %ymm1, %ymm14
    vpsllw 16(%r15,%rcx,2), %ymm14, %ymm3
    vpsllw -4(%rdx,%r14,4), %ymm3, %ymm8
    vpslld $0x7f, %xmm3, %xmm0
    vpslld $0xff, %xmm15, %xmm2
    vpslld $0, %xmm1, %xmm14
    vpslld $0x7f, %xmm12, %xmm8
    vpslld $0, %ymm1, %ymm6
    vpslld $0x7f, %ymm12, %ymm0
    vpslld $0xff, %ymm7, %ymm11
    vpslld $0, %ymm9, %ymm14
    vpslld %xmm7, %xmm2, %xmm1
    vpslld %xmm9, %xmm6, %xmm3
    vpslld %xmm3, %xmm8, %xmm7
    vpslld %xmm15, %xmm11, %xmm1
    vpslld %xmm1, %xmm6, %xmm12
    vpslld %xmm12, %xmm0, %xmm15
    vpslld %xmm7, %xmm11, %xmm9
    vpslld %xmm9, %xmm14, %xmm12
    vpslld (%rax), %xmm14, %xmm3
    vpslld 8(%rsp), %xmm3, %xmm8
    vpslld -200(%rbp), %xmm8, %xmm7
    vpslld (%r12), %xmm7, %xmm11
    vpslld 0x40(%r13), %xmm11, %xmm1
    vpslld (%rax,%r9,8), %xmm1, %xmm14
    vpslld 16(%r15,%rcx,2), %xmm14, %xmm3
    vpslld -4(%rdx,%r14,4), %xmm3, %xmm8
    vpslld %xmm3, %ymm0, %ymm7
    vpslld %xmm15, %ymm2, %ymm1
    vpslld %xmm1, %ymm14, %ymm3
    vpslld %xmm12, %ymm8, %ymm7
    vpslld %xmm7, %ymm2, %ymm9
    vpslld %xmm9, %ymm6, %ymm12
    vpslld %xmm3, %ymm8, %ymm15
    vpslld %xmm15, %ymm11, %ymm9
    vpslld (%rax), %ymm14, %ymm3
    vpslld 8(%rsp), %ymm3, %ymm8
    vpslld -200(%rbp), %ymm8, %ymm7
    vpslld (%r12), %ymm7, %ymm11
    vpslld 0x40(%r13), %ymm11, %ymm1
    vpslld (%rax,%r9,8), %ymm1, %ymm14
    vpslld 16(%r15,%rcx,2), %ymm14, %ymm3
    vpslld -4(%rdx,%r14,4), %ymm3, %ymm8
    vpsllq $0, %xmm1, %xmm6
    vpsllq $0x7f, %xmm12, %xmm0
    vpsllq $0xff, %xmm7, %xmm11
    vpsllq $0, %xmm9, %xmm14
    vpsllq $0xff, %ymm7, %ymm2
    vpsllq $0, %ymm9, %ymm6
    vpsllq $0x7f, %ymm3, %ymm8
    vpsllq $0xff, %ymm15, %ymm11
    vpsllq %xmm3, %xmm0, %xmm7
    vpsllq %xmm15, %xmm2, %xmm1
    vpsllq %xmm1, %xmm14, %xmm3
    vpsllq %xmm12, %xmm8, %xmm7
    vpsllq %xmm7, %xmm2, %xmm9
    vpsllq %xmm9, %xmm6, %xmm12
    vpsllq %xmm3, %xmm8, %xmm15
    vpsllq %xmm15, %xmm11, %xmm9
    vpsllq (%rax), %xmm14, %xmm3
    vpsllq 8(%rsp), %xmm3, %xmm8
    vpsllq -200(%rbp), %xmm8, %xmm7
    vpsllq (%r12), %xmm7, %xmm11
    vpsllq 0x40(%r13), %xmm11, %xmm1
    vpsllq (%rax,%r9,8), %xmm1, %xmm14
    vpsllq 16(%r15,%rcx,2), %xmm14, %xmm3
    vpsllq -4(%rdx,%r14,4), %xmm3, %xmm8
    vpsllq %xmm1, %ymm6, %ymm3
    vpsllq %xmm12, %ymm0, %ymm7
    vpsllq %xmm7, %ymm11, %ymm1
    vpsllq %xmm9, %ymm14, %ymm3
    vpsllq %xmm3, %ymm0, %ymm15
    vpsllq %xmm15, %ymm2, %ymm9
    vpsllq %xmm1, %ymm14, %ymm12
    vpsllq %xmm12, %ymm8, %ymm15
    vpsllq (%rax), %ymm14, %ymm3
    vpsllq 8(%rsp), %ymm3, %ymm8
    vpsllq -200(%rbp), %ymm8, %ymm7
    vpsllq (%r12), %ymm7, %ymm11
    vpsllq 0x40(%r13), %ymm11, %ymm1
    vpsllq (%rax,%r9,8), %ymm1, %ymm14
    vpsllq 16(%r15,%rcx,2), %ymm14, %ymm3
    vpsllq -4(%rdx,%r14,4), %ymm3, %ymm8
    vpsrlw $0xff, %xmm7, %xmm2
    vpsrlw $0, %xmm9, %xmm6
    vpsrlw $0x7f, %xmm3, %xmm8
    vpsrlw $0xff, %xmm15, %xmm11
    vpsrlw $0x7f, %ymm3, %ymm0
    vpsrlw $0xff, %ymm15, %ymm2
    vpsrlw $0, %ymm1, %ymm14
    vpsrlw $0x7f, %ymm12, %ymm8
    vpsrlw %xmm1, %xmm6, %xmm3
    vpsrlw %xmm12, %xmm0, %xmm7
    vpsrlw %xmm7, %xmm11, %xmm1
    vpsrlw %xmm9, %xmm14, %xmm3
    vpsrlw %xmm3, %xmm0, %xmm15
    vpsrlw %xmm15, %xmm2, %xmm9
    vpsrlw %xmm1, %xmm14, %xmm12
    vpsrlw %xmm12, %xmm8, %xmm15
    vpsrlw (%rax), %xmm14, %xmm3
    vpsrlw 8(%rsp), %xmm3, %xmm8
    vpsrlw -200(%rbp), %xmm8, %xmm7
    vpsrlw (%r12), %xmm7, %xmm11
    vpsrlw 0x40(%r13), %xmm11, %xmm1
    vpsrlw (%rax,%r9,8), %xmm1, %xmm14
    vpsrlw 16(%r15,%rcx,2), %xmm14, %xmm3
    vpsrlw -4(%rdx,%r14,4), %xmm3, %xmm8
    vpsrlw %xmm7, %ymm2, %ymm1
    vpsrlw %xmm9, %ymm6, %ymm3
    vpsrlw %xmm3, %ymm8, %ymm7
    vpsrlw %xmm15, %ymm11, %ymm1
    vpsrlw %xmm1, %ymm6, %ymm12
    vpsrlw %xmm12, %ymm0, %ymm15
    vpsrlw %xmm7, %ymm11, %ymm9
    vpsrlw %xmm9, %ymm14, %ymm12
    vpsrlw (%rax), %ymm14, %ymm3
    vpsrlw 8(%rsp), %ymm3, %ymm8
    vpsrlw -200(%rbp), %ymm8, %ymm7
    vpsrlw (%r12), %ymm7, %ymm11
    vpsrlw 0x40(%r13), %ymm11, %ymm1
    vpsrlw (%rax,%r9,8), %ymm1, %ymm14
    vpsrlw 16(%r15,%rcx,2), %ymm14, %ymm3
    vpsrlw -4(%rdx,%r14,4), %ymm3, %ymm8
    vpsrld $0x7f, %xmm3, %xmm0
    vpsrld $0xff, %xmm15, %xmm2
    vpsrld $0, %xmm1, %xmm14
    vpsrld $0x7f, %xmm12, %xmm8
    vpsrld $0, %ymm1, %ymm6
    vpsrld $0x7f, %ymm12, %ymm0
    vpsrld $0xff, %ymm7, %ymm11
    vpsrld $0, %ymm9, %ymm14
    vpsrld %xmm7, %xmm2, %xmm1
    vpsrld %xmm9, %xmm6, %xmm3
    vpsrld %xmm3, %xmm8, %xmm7
    vpsrld %xmm15, %xmm11, %xmm1
    vpsrld %xmm1, %xmm6, %xmm12
    vpsrld %xmm12, %xmm0, %xmm15
    vpsrld %xmm7, %xmm11, %xmm9
    vpsrld %xmm9, %xmm14, %xmm12
    vpsrld (%rax), %xmm14, %xmm3
    vpsrld 8(%rsp), %xmm3, %xmm8
    vpsrld -200(%rbp), %xmm8, %xmm7
    vpsrld (%r12), %xmm7, %xmm11
    vpsrld 0x40(%r13), %xmm11, %xmm1
    vpsrld (%rax,%r9,8), %xmm1, %xmm14
    vpsrld 16(%r15,%rcx,2), %xmm14, %xmm3
    vpsrld -4(%rdx,%r14,4), %xmm3, %xmm8
    vpsrld %xmm3, %ymm0, %ymm7
    vpsrld %xmm15, %ymm2, %ymm1
    vpsrld %xmm1, %ymm14, %ymm3
    vpsrld %xmm12, %ymm8, %ymm7
    vpsrld %xmm7, %ymm2, %ymm9
    vpsrld %xmm9, %ymm6, %ymm12
    vpsrld %xmm3, %ymm8, %ymm15
    vpsrld %xmm15, %ymm11, %ymm9
    vpsrld (%rax), %ymm14, %ymm3
    vpsrld 8(%rsp), %ymm3, %ymm8
    vpsrld -200(%rbp), %ymm8, %ymm7
    vpsrld (%r12), %ymm7, %ymm11
    vpsrld 0x40(%r13), %ymm11, %ymm1
    vpsrld (%rax,%r9,8), %ymm1, %ymm14
    vpsrld 16(%r15,%rcx,2), %ymm14, %ymm3
    vpsrld -4(%rdx,%r14,4), %ymm3, %ymm8
    vpsrlq $0, %xmm1, %xmm6
    vpsrlq $0x7f, %xmm12, %xmm0
    vpsrlq $0xff, %xmm7, %xmm11
    vpsrlq $0, %xmm9, %xmm14
    vpsrlq $0xff, %ymm7, %ymm2
    vpsrlq $0, %ymm9, %ymm6
    vpsrlq $0x7f, %ymm3, %ymm8
    vpsrlq $0xff, %ymm15, %ymm11
    vpsrlq %xmm3, %xmm0, %xmm7
    vpsrlq %xmm15, %xmm2, %xmm1
    vpsrlq %xmm1, %xmm14, %xmm3
    vpsrlq %xmm12, %xmm8, %xmm7
    vpsrlq %xmm7, %xmm2, %xmm9
    vpsrlq %xmm9, %xmm6, %xmm12
    vpsrlq %xmm3, %xmm8, %xmm15
    vpsrlq %xmm15, %xmm11, %xmm9
    vpsrlq (%rax), %xmm14, %xmm3
    vpsrlq 8(%rsp), %xmm3, %xmm8
    vpsrlq -200(%rbp), %xmm8, %xmm7
    vpsrlq (%r12), %xmm7, %xmm11
    vpsrlq 0x40(%r13), %xmm11, %xmm1
    vpsrlq (%rax,%r9,8), %xmm1, %xmm14
    vpsrlq 16(%r15,%rcx,2), %xmm14, %xmm3
    vpsrlq -4(%rdx,%r14,4), %xmm3, %xmm8
    vpsrlq %xmm1, %ymm6, %ymm3
    vpsrlq %xmm12, %ymm0, %ymm7
    vpsrlq %xmm7, %ymm11, %ymm1
    vpsrlq %xmm9, %ymm14, %ymm3
    vpsrlq %xmm3, %ymm0, %ymm15
    vpsrlq %xmm15, %ymm2, %ymm9
    vpsrlq %xmm1, %ymm14, %ymm12
    vpsrlq %xmm12, %ymm8, %ymm15
    vpsrlq (%rax), %ymm14, %ymm3
    vpsrlq 8(%rsp), %ymm3, %ymm8
    vpsrlq -200(%rbp), %ymm8, %ymm7
    vpsrlq (%r12), %ymm7, %ymm11
    vpsrlq 0x40(%r13), %ymm11, %ymm1
    vpsrlq (%rax,%r9,8), %ymm1, %ymm14
    vpsrlq 16(%r15,%rcx,2), %ymm14, %ymm3
    vpsrlq -4(%rdx,%r14,4), %ymm3, %ymm8
    vpsraw $0xff, %xmm7, %xmm2
    vpsraw $0, %xmm9, %xmm6
    vpsraw $0x7f, %xmm3, %xmm8
    vpsraw $0xff, %xmm15, %xmm11
    vpsraw $0x7f, %ymm3, %ymm0
    vpsraw $0xff, %ymm15, %ymm2
    vpsraw $0, %ymm1, %ymm14
    vpsraw $0x7f, %ymm12, %ymm8
    vpsraw %xmm1, %xmm6, %xmm3
    vpsraw %xmm12, %xmm0, %xmm7
    vpsraw %xmm7, %xmm11, %xmm1
    vpsraw %xmm9, %xmm14, %xmm3
    vpsraw %xmm3, %xmm0, %xmm15
    vpsraw %xmm15, %xmm2, %xmm9
    vpsraw %xmm1, %xmm14, %xmm12
    vpsraw %xmm12, %xmm8, %xmm15
    vpsraw (%rax), %xmm14, %xmm3
    vpsraw 8(%rsp), %xmm3, %xmm8
    vpsraw -200(%rbp), %xmm8, %xmm7
    vpsraw (%r12), %xmm7, %xmm11
    vpsraw 0x40(%r13), %xmm11, %xmm1
    vpsraw (%rax,%r9,8), %xmm1, %xmm14
    vpsraw 16(%r15,%rcx,2), %xmm14, %xmm3
    vpsraw -4(%rdx,%r14,4), %xmm3, %xmm8
    vpsraw %xmm7, %ymm2, %ymm1
    vpsraw %xmm9, %ymm6, %ymm3
    vpsraw %xmm3, %ymm8, %ymm7
    vpsraw %xmm15, %ymm11, %ymm1
    vpsraw %xmm1, %ymm6, %ymm12
    vpsraw %xmm12, %ymm0, %ymm15
    vpsraw %xmm7, %ymm11, %ymm9
    vpsraw %xmm9, %ymm14, %ymm12
    vpsraw (%rax), %ymm14, %ymm3
    vpsraw 8(%rsp), %ymm3, %ymm8
    vpsraw -200(%rbp), %ymm8, %ymm7
    vpsraw (%r12), %ymm7, %ymm11
    vpsraw 0x40(%r13), %ymm11, %ymm1
    vpsraw (%rax,%r9,8), %ymm1, %ymm14
    vpsraw 16(%r15,%rcx,2), %ymm14, %ymm3
    vpsraw -4(%rdx,%r14,4), %ymm3, %ymm8
    vpsrad $0x7f, %xmm3, %xmm0
    vpsrad $0xff, %xmm15, %xmm2
    vpsrad $0, %xmm1, %xmm14
    vpsrad $0x7f, %xmm12, %xmm8
    vpsrad $0, %ymm1, %ymm6
    vpsrad $0x7f, %ymm12, %ymm0
    vpsrad $0xff, %ymm7, %ymm11
    vpsrad $0, %ymm9, %ymm14
    vpsrad %xmm7, %xmm2, %xmm1
    vpsrad %xmm9, %xmm6, %xmm3
    vpsrad %xmm3, %xmm8, %xmm7
    vpsrad %xmm15, %xmm11, %xmm1
    vpsrad %xmm1, %xmm6, %xmm12
    vpsrad %xmm12, %xmm0, %xmm15
    vpsrad %xmm7, %xmm11, %xmm9
    vpsrad %xmm9, %xmm14, %xmm12
    vpsrad (%rax), %xmm14, %xmm3
    vpsrad 8(%rsp), %xmm3, %xmm8
    vpsrad -200(%rbp), %xmm8, %xmm7
    vpsrad (%r12), %xmm7, %xmm11
    vpsrad 0x40(%r13), %xmm11, %xmm1
    vpsrad (%rax,%r9,8), %xmm1, %xmm14
    vpsrad 16(%r15,%rcx,2), %xmm14, %xmm3
    vpsrad -4(%rdx,%r14,4), %xmm3, %xmm8
    vpsrad %xmm3, %ymm0, %ymm7
    vpsrad %xmm15, %ymm2, %ymm1
    vpsrad %xmm1, %ymm14, %ymm3
    vpsrad %xmm12, %ymm8, %ymm7
    vpsrad %xmm7, %ymm2, %ymm9
    vpsrad %xmm9, %ymm6, %ymm12
    vpsrad %xmm3, %ymm8, %ymm15
    vpsrad %xmm15, %ymm11, %ymm9
    vpsrad (%rax), %ymm14, %ymm3
    vpsrad 8(%rsp), %ymm3, %ymm8
    vpsrad -200(%rbp), %ymm8, %ymm7
    vpsrad (%r12), %ymm7, %ymm11
    vpsrad 0x40(%r13), %ymm11, %ymm1
    vpsrad (%rax,%r9,8), %ymm1, %ymm14
    vpsrad 16(%r15,%rcx,2), %ymm14, %ymm3
    vpsrad -4(%rdx,%r14,4), %ymm3, %ymm8
    vpslldq $0, %xmm1, %xmm6
    vpslldq $0x7f, %xmm12, %xmm0
    vpslldq $0xff, %xmm7, %xmm11
    vpslldq $0, %xmm9, %xmm14
    vpslldq $0xff, %ymm7, %ymm2
    vpslldq $0, %ymm9, %ymm6
    vpslldq $0x7f, %ymm3, %ymm8
    vpslldq $0xff, %ymm15, %ymm11
    vpsrldq $0x7f, %xmm3, %xmm0
    vpsrldq $0xff, %xmm15, %xmm2
    vpsrldq $0, %xmm1, %xmm14
    vpsrldq $0x7f, %xmm12, %xmm8
    vpsrldq $0, %ymm1, %ymm6
    vpsrldq $0x7f, %ymm12, %ymm0
    vpsrldq $0xff, %ymm7, %ymm11
    vpsrldq $0, %ymm9, %ymm14
    vfmadd132ps %xmm7, %xmm2, %xmm1
    vfmadd132ps %xmm9, %xmm6, %xmm3
    vfmadd132ps %xmm3, %xmm8, %xmm7
    vfmadd132ps %xmm15, %xmm11, %xmm1
    vfmadd132ps %xmm1, %xmm6, %xmm12
    vfmadd132ps %xmm12, %xmm0, %xmm15
    vfmadd132ps %xmm7, %xmm11, %xmm9
    vfmadd132ps %xmm9, %xmm14, %xmm12
    vfmadd132ps (%rax), %xmm14, %xmm3
    vfmadd132ps 8(%rsp), %xmm3, %xmm8
    vfmadd132ps -200(%rbp), %xmm8, %xmm7
    vfmadd132ps (%r12), %xmm7, %xmm11
    vfmadd132ps 0x40(%r13), %xmm11, %xmm1
    vfmadd132ps (%rax,%r9,8), %xmm1, %xmm14
    vfmadd132ps 16(%r15,%rcx,2), %xmm14, %xmm3
    vfmadd132ps -4(%rdx,%r14,4), %xmm3, %xmm8
    vfmadd132ps %ymm3, %ymm0, %ymm7
    vfmadd132ps %ymm15, %ymm2, %ymm1
    vfmadd132ps %ymm1, %ymm14, %ymm3
    vfmadd132ps %ymm12, %ymm8, %ymm7
    vfmadd132ps %ymm7, %ymm2, %ymm9
    vfmadd132ps %ymm9, %ymm6, %ymm12
    vfmadd132ps %ymm3, %ymm8, %ymm15
    vfmadd132ps %ymm15, %ymm11, %ymm9
    vfmadd132ps (%rax), %ymm14, %ymm3
    vfmadd132ps 8(%rsp), %ymm3, %ymm8
    vfmadd132ps -200(%rbp), %ymm8, %ymm7
    vfmadd132ps (%r12), %ymm7, %ymm11
    vfmadd132ps 0x40(%r13), %ymm11, %ymm1
    vfmadd132ps (%rax,%r9,8), %ymm1, %ymm14
    vfmadd132ps 16(%r15,%rcx,2), %ymm14, %ymm3
    vfmadd132ps -4(%rdx,%r14,4), %ymm3, %ymm8
    vfmadd132pd %xmm1, %xmm6, %xmm3
    vfmadd132pd %xmm12, %xmm0, %xmm7
    vfmadd132pd %xmm7, %xmm11, %xmm1
    vfmadd132pd %xmm9, %xmm14, %xmm3
    vfmadd132pd %xmm3, %xmm0, %xmm15
    vfmadd132pd %xmm15, %xmm2, %xmm9
    vfmadd132pd %xmm1, %xmm14, %xmm12
    vfmadd132pd %xmm12, %xmm8, %xmm15
    vfmadd132pd (%rax), %xmm14, %xmm3
    vfmadd132pd 8(%rsp), %xmm3, %xmm8
    vfmadd132pd -200(%rbp), %xmm8, %xmm7
    vfmadd132pd (%r12), %xmm7, %xmm11
    vfmadd132pd 0x40(%r13), %xmm11, %xmm1
    vfmadd132pd (%rax,%r9,8), %xmm1, %xmm14
    vfmadd132pd 16(%r15,%rcx,2), %xmm14, %xmm3
    vfmadd132pd -4(%rdx,%r14,4), %xmm3, %xmm8
    vfmadd132pd %ymm7, %ymm2, %ymm1
    vfmadd132pd %ymm9, %ymm6, %ymm3
    vfmadd132pd %ymm3, %ymm8, %ymm7
    vfmadd132pd %ymm15, %ymm11, %ymm1
    vfmadd132pd %ymm1, %ymm6, %ymm12
    vfmadd132pd %ymm12, %ymm0, %ymm15
    vfmadd132pd %ymm7, %ymm11, %ymm9
    vfmadd132pd %ymm9, %ymm14, %ymm12
    vfmadd132pd (%rax), %ymm14, %ymm3
    vfmadd132pd 8(%rsp), %ymm3, %ymm8
    vfmadd132pd -200(%rbp), %ymm8, %ymm7
    vfmadd132pd (%r12), %ymm7, %ymm11
    vfmadd132pd 0x40(%r13), %ymm11, %ymm1
    vfmadd132pd (%rax,%r9,8), %ymm1, %ymm14
    vfmadd132pd 16(%r15,%rcx,2), %ymm14, %ymm3
    vfmadd132pd -4(%rdx,%r14,4), %ymm3, %ymm8
    vfmadd213ps %xmm3, %xmm0, %xmm7
    vfmadd213ps %xmm15, %xmm2, %xmm1
    vfmadd213ps %xmm1, %xmm14, %xmm3
    vfmadd213ps %xmm12, %xmm8, %xmm7
    vfmadd213ps %xmm7, %xmm2, %xmm9
    vfmadd213ps %xmm9, %xmm6, %xmm12
    vfmadd213ps %xmm3, %xmm8, %xmm15
    vfmadd213ps %xmm15, %xmm11, %xmm9
    vfmadd213ps (%rax), %xmm14, %xmm3
    vfmadd213ps 8(%rsp), %xmm3, %xmm8
    vfmadd213ps -200(%rbp), %xmm8, %xmm7
    vfmadd213ps (%r12), %xmm7, %xmm11
    vfmadd213ps 0x40(%r13), %xmm11, %xmm1
    vfmadd213ps (%rax,%r9,8), %xmm1, %xmm14
    vfmadd213ps 16(%r15,%rcx,2), %xmm14, %xmm3
    vfmadd213ps -4(%rdx,%r14,4), %xmm3, %xmm8
    vfmadd213ps %ymm1, %ymm6, %ymm3
    vfmadd213ps %ymm12, %ymm0, %ymm7
    vfmadd213ps %ymm7, %ymm11, %ymm1
    vfmadd213ps %ymm9, %ymm14, %ymm3
    vfmadd213ps %ymm3, %ymm0, %ymm15
    vfmadd213ps %ymm15, %ymm2, %ymm9
    vfmadd213ps %ymm1, %ymm14, %ymm12
    vfmadd213ps %ymm12, %ymm8, %ymm15
    vfmadd213ps (%rax), %ymm14, %ymm3
    vfmadd213ps 8(%rsp), %ymm3, %ymm8
    vfmadd213ps -200(%rbp), %ymm8, %ymm7
    vfmadd213ps (%r12), %ymm7, %ymm11
    vfmadd213ps 0x40(%r13), %ymm11, %ymm1
    vfmadd213ps (%rax,%r9,8), %ymm1, %ymm14
    vfmadd213ps 16(%r15,%rcx,2), %ymm14, %ymm3
    vfmadd213ps -4(%rdx,%r14,4), %ymm3, %ymm8
    vfmadd213pd %xmm7, %xmm2, %xmm1
    vfmadd213pd %xmm9, %xmm6, %xmm3
    vfmadd213pd %xmm3, %xmm8, %xmm7
    vfmadd213pd %xmm15, %xmm11, %xmm1
    vfmadd213pd %xmm1, %xmm6, %xmm12
    vfmadd213pd %xmm12, %xmm0, %xmm15
    vfmadd213pd %xmm7, %xmm11, %xmm9
    vfmadd213pd %xmm9, %xmm14, %xmm12
    vfmadd213pd (%rax), %xmm14, %xmm3
    vfmadd213pd 8(%rsp), %xmm3, %xmm8
    vfmadd213pd -200(%rbp), %xmm8, %xmm7
    vfmadd213pd (%r12), %xmm7, %xmm11
    vfmadd213pd 0x40(%r13), %xmm11, %xmm1
    vfmadd213pd (%rax,%r9,8), %xmm1, %xmm14
    vfmadd213pd 16(%r15,%rcx,2), %xmm14, %xmm3
    vfmadd213pd -4(%rdx,%r14,4), %xmm3, %xmm8
    vfmadd213pd %ymm3, %ymm0, %ymm7
    vfmadd213pd %ymm15, %ymm2, %ymm1
    vfmadd213pd %ymm1, %ymm14, %ymm3
    vfmadd213pd %ymm12, %ymm8, %ymm7
    vfmadd213pd %ymm7, %ymm2, %ymm9
    vfmadd213pd %ymm9, %ymm6, %ymm12
    vfmadd213pd %ymm3, %ymm8, %ymm15
    vfmadd213pd %ymm15, %ymm11, %ymm9
    vfmadd213pd (%rax), %ymm14, %ymm3
    vfmadd213pd 8(%rsp), %ymm3, %ymm8
    vfmadd213pd -200(%rbp), %ymm8, %ymm7
    vfmadd213pd (%r12), %ymm7, %ymm11
    vfmadd213pd 0x40(%r13), %ymm11, %ymm1
    vfmadd213pd (%rax,%r9,8), %ymm1, %ymm14
    vfmadd213pd 16(%r15,%rcx,2), %ymm14, %ymm3
    vfmadd213pd -4(%rdx,%r14,4), %ymm3, %ymm8
    vfmadd231ps %xmm1, %xmm6, %xmm3
    vfmadd231ps %xmm12, %xmm0, %xmm7
    vfmadd231ps %xmm7, %xmm11, %xmm1
    vfmadd231ps %xmm9, %xmm14, %xmm3
    vfmadd231ps %xmm3, %xmm0, %xmm15
    vfmadd231ps %xmm15, %xmm2, %xmm9
    vfmadd231ps %xmm1, %xmm14, %xmm12
    vfmadd231ps %xmm12, %xmm8, %xmm15
    vfmadd231ps (%rax), %xmm14, %xmm3
    vfmadd231ps 8(%rsp), %xmm3, %xmm8
    vfmadd231ps -200(%rbp), %xmm8, %xmm7
    vfmadd231ps (%r12), %xmm7, %xmm11
    vfmadd231ps 0x40(%r13), %xmm11, %xmm1
    vfmadd231ps (%rax,%r9,8), %xmm1, %xmm14
    vfmadd231ps 16(%r15,%rcx,2), %xmm14, %xmm3
    vfmadd231ps -4(%rdx,%r14,4), %xmm3, %xmm8
    vfmadd231ps %ymm7, %ymm2, %ymm1
    vfmadd231ps %ymm9, %ymm6, %ymm3
    vfmadd231ps %ymm3, %ymm8, %ymm7
    vfmadd231ps %ymm15, %ymm11, %ymm1
    vfmadd231ps %ymm1, %ymm6, %ymm12
    vfmadd231ps %ymm12, %ymm0, %ymm15
    vfmadd231ps %ymm7, %ymm11, %ymm9
    vfmadd231ps %ymm9, %ymm14, %ymm12
    vfmadd231ps (%rax), %ymm14, %ymm3
    vfmadd231ps 8(%rsp), %ymm3, %ymm8
    vfmadd231ps -200(%rbp), %ymm8, %ymm7
    vfmadd231ps (%r12), %ymm7, %ymm11
    vfmadd231ps 0x40(%r13), %ymm11, %ymm1
    vfmadd231ps (%rax,%r9,8), %ymm1, %ymm14
    vfmadd231ps 16(%r15,%rcx,2), %ymm14, %ymm3
    vfmadd231ps -4(%rdx,%r14,4), %ymm3, %ymm8
    vfmadd231pd %xmm3, %xmm0, %xmm7
    vfmadd231pd %xmm15, %xmm2, %xmm1
    vfmadd231pd %xmm1, %xmm14, %xmm3
    vfmadd231pd %xmm12, %xmm8, %xmm7
    vfmadd231pd %xmm7, %xmm2, %xmm9
    vfmadd231pd %xmm9, %xmm6, %xmm12
    vfmadd231pd %xmm3, %xmm8, %xmm15
    vfmadd231pd %xmm15, %xmm11, %xmm9
    vfmadd231pd (%rax), %xmm14, %xmm3
    vfmadd231pd 8(%rsp), %xmm3, %xmm8
    vfmadd231pd -200(%rbp), %xmm8, %xmm7
    vfmadd231pd (%r12), %xmm7, %xmm11
    vfmadd231pd 0x40(%r13), %xmm11, %xmm1
    vfmadd231pd (%rax,%r9,8), %xmm1, %xmm14
    vfmadd231pd 16(%r15,%rcx,2), %xmm14, %xmm3
    vfmadd231pd -4(%rdx,%r14,4), %xmm3, %xmm8
    vfmadd231pd %ymm1, %ymm6, %ymm3
    vfmadd231pd %ymm12, %ymm0, %ymm7
    vfmadd231pd %ymm7, %ymm11, %ymm1
    vfmadd231pd %ymm9, %ymm14, %ymm3
    vfmadd231pd %ymm3, %ymm0, %ymm15
    vfmadd231pd %ymm15, %ymm2, %ymm9
    vfmadd231pd %ymm1, %ymm14, %ymm12
    vfmadd231pd %ymm12, %ymm8, %ymm15
    vfmadd231pd (%rax), %ymm14, %ymm3
    vfmadd231pd 8(%rsp), %ymm3, %ymm8
    vfmadd231pd -200(%rbp), %ymm8, %ymm7
    vfmadd231pd (%r12), %ymm7, %ymm11
    vfmadd231pd 0x40(%r13), %ymm11, %ymm1
    vfmadd231pd (%rax,%r9,8), %ymm1, %ymm14
    vfmadd231pd 16(%r15,%rcx,2), %ymm14, %ymm3
    vfmadd231pd -4(%rdx,%r14,4), %ymm3, %ymm8
    vfmsub132ps %xmm7, %xmm2, %xmm1
    vfmsub132ps %xmm9, %xmm6, %xmm3
    vfmsub132ps %xmm3, %xmm8, %xmm7
    vfmsub132ps %xmm15, %xmm11, %xmm1
    vfmsub132ps %xmm1, %xmm6, %xmm12
    vfmsub132ps %xmm12, %xmm0, %xmm15
    vfmsub132ps %xmm7, %xmm11, %xmm9
    vfmsub132ps %xmm9, %xmm14, %xmm12
    vfmsub132ps (%rax), %xmm14, %xmm3
    vfmsub132ps 8(%rsp), %xmm3, %xmm8
    vfmsub132ps -200(%rbp), %xmm8, %xmm7
    vfmsub132ps (%r12), %xmm7, %xmm11
    vfmsub132ps 0x40(%r13), %xmm11, %xmm1
    vfmsub132ps (%rax,%r9,8), %xmm1, %xmm14
    vfmsub132ps 16(%r15,%rcx,2), %xmm14, %xmm3
    vfmsub132ps -4(%rdx,%r14,4), %xmm3, %xmm8
    vfmsub132ps %ymm3, %ymm0, %ymm7
    vfmsub132ps %ymm15, %ymm2, %ymm1
    vfmsub132ps %ymm1, %ymm14, %ymm3
    vfmsub132ps %ymm12, %ymm8, %ymm7
    vfmsub132ps %ymm7, %ymm2, %ymm9
    vfmsub132ps %ymm9, %ymm6, %ymm12
    vfmsub132ps %ymm3, %ymm8, %ymm15
    vfmsub132ps %ymm15, %ymm11, %ymm9
    vfmsub132ps (%rax), %ymm14, %ymm3
    vfmsub132ps 8(%rsp), %ymm3, %ymm8
    vfmsub132ps -200(%rbp), %ymm8, %ymm7
    vfmsub132ps (%r12), %ymm7, %ymm11
    vfmsub132ps 0x40(%r13), %ymm11, %ymm1
    vfmsub132ps (%rax,%r9,8), %ymm1, %ymm14
    vfmsub132ps 16(%r15,%rcx,2), %ymm14, %ymm3
    vfmsub132ps -4(%rdx,%r14,4), %ymm3, %ymm8
    vfmsub132pd %xmm1, %xmm6, %xmm3
    vfmsub132pd %xmm12, %xmm0, %xmm7
    vfmsub132pd %xmm7, %xmm11, %xmm1
    vfmsub132pd %xmm9, %xmm14, %xmm3
    vfmsub132pd %xmm3, %xmm0, %xmm15
    vfmsub132pd %xmm15, %xmm2, %xmm9
    vfmsub132pd %xmm1, %xmm14, %xmm12
    vfmsub132pd %xmm12, %xmm8, %xmm15
    vfmsub132pd (%rax), %xmm14, %xmm3
    vfmsub132pd 8(%rsp), %xmm3, %xmm8
    vfmsub132pd -200(%rbp), %xmm8, %xmm7
    vfmsub132pd (%r12), %xmm7, %xmm11
    vfmsub132pd 0x40(%r13), %xmm11, %xmm1
    vfmsub132pd (%rax,%r9,8), %xmm1, %xmm14
    vfmsub132pd 16(%r15,%rcx,2), %xmm14, %xmm3
    vfmsub132pd -4(%rdx,%r14,4), %xmm3, %xmm8
    vfmsub132pd %ymm7, %ymm2, %ymm1
    vfmsub132pd %ymm9, %ymm6, %ymm3
    vfmsub132pd %ymm3, %ymm8, %ymm7
    vfmsub132pd %ymm15, %ymm11, %ymm1
    vfmsub132pd %ymm1, %ymm6, %ymm12
    vfmsub132pd %ymm12, %ymm0, %ymm15
    vfmsub132pd %ymm7, %ymm11, %ymm9
    vfmsub132pd %ymm9, %ymm14, %ymm12
    vfmsub132pd (%rax), %ymm14, %ymm3
    vfmsub132pd 8(%rsp), %ymm3, %ymm8
    vfmsub132pd -200(%rbp), %ymm8, %ymm7
    vfmsub132pd (%r12), %ymm7, %ymm11
    vfmsub132pd 0x40(%r13), %ymm11, %ymm1
    vfmsub132pd (%rax,%r9,8), %ymm1, %ymm14
    vfmsub132pd 16(%r15,%rcx,2), %ymm14, %ymm3
    vfmsub132pd -4(%rdx,%r14,4), %ymm3, %ymm8
    vfmsub213ps %xmm3, %xmm0, %xmm7
    vfmsub213ps %xmm15, %xmm2, %xmm1
    vfmsub213ps %xmm1, %xmm14, %xmm3
    vfmsub213ps %xmm12, %xmm8, %xmm7
    vfmsub213ps %xmm7, %xmm2, %xmm9
    vfmsub213ps %xmm9, %xmm6, %xmm12
    vfmsub213ps %xmm3, %xmm8, %xmm15
    vfmsub213ps %xmm15, %xmm11, %xmm9
    vfmsub213ps (%rax), %xmm14, %xmm3
    vfmsub213ps 8(%rsp), %xmm3, %xmm8
    vfmsub213ps -200(%rbp), %xmm8, %xmm7
    vfmsub213ps (%r12), %xmm7, %xmm11
    vfmsub213ps 0x40(%r13), %xmm11, %xmm1
    vfmsub213ps (%rax,%r9,8), %xmm1, %xmm14
    vfmsub213ps 16(%r15,%rcx,2), %xmm14, %xmm3
    vfmsub213ps -4(%rdx,%r14,4), %xmm3, %xmm8
    vfmsub213ps %ymm1, %ymm6, %ymm3
    vfmsub213ps %ymm12, %ymm0, %ymm7
    vfmsub213ps %ymm7, %ymm11, %ymm1
    vfmsub213ps %ymm9, %ymm14, %ymm3
    vfmsub213ps %ymm3, %ymm0, %ymm15
    vfmsub213ps %ymm15, %ymm2, %ymm9
    vfmsub213ps %ymm1, %ymm14, %ymm12
    vfmsub213ps %ymm12, %ymm8, %ymm15
    vfmsub213ps (%rax), %ymm14, %ymm3
    vfmsub213ps 8(%rsp), %ymm3, %ymm8
    vfmsub213ps -200(%rbp), %ymm8, %ymm7
    vfmsub213ps (%r12), %ymm7, %ymm11
    vfmsub213ps 0x40(%r13), %ymm11, %ymm1
    vfmsub213ps (%rax,%r9,8), %ymm1, %ymm14
    vfmsub213ps 16(%r15,%rcx,2), %ymm14, %ymm3
    vfmsub213ps -4(%rdx,%r14,4), %ymm3, %ymm8
    vfmsub213pd %xmm7, %xmm2, %xmm1
    vfmsub213pd %xmm9, %xmm6, %xmm3
    vfmsub213pd %xmm3, %xmm8, %xmm7
    vfmsub213pd %xmm15, %xmm11, %xmm1
    vfmsub213pd %xmm1, %xmm6, %xmm12
    vfmsub213pd %xmm12, %xmm0, %xmm15
    vfmsub213pd %xmm7, %xmm11, %xmm9
    vfmsub213pd %xmm9, %xmm14, %xmm12
    vfmsub213pd (%rax), %xmm14, %xmm3
    vfmsub213pd 8(%rsp), %xmm3, %xmm8
    vfmsub213pd -200(%rbp), %xmm8, %xmm7
    vfmsub213pd (%r12), %xmm7, %xmm11
    vfmsub213pd 0x40(%r13), %xmm11, %xmm1
    vfmsub213pd (%rax,%r9,8), %xmm1, %xmm14
    vfmsub213pd 16(%r15,%rcx,2), %xmm14, %xmm3
    vfmsub213pd -4(%rdx,%r14,4), %xmm3, %xmm8
    vfmsub213pd %ymm3, %ymm0, %ymm7
    vfmsub213pd %ymm15, %ymm2, %ymm1
    vfmsub213pd %ymm1, %ymm14, %ymm3
    vfmsub213pd %ymm12, %ymm8, %ymm7
    vfmsub213pd %ymm7, %ymm2, %ymm9
    vfmsub213pd %ymm9, %ymm6, %ymm12
    vfmsub213pd %ymm3, %ymm8, %ymm15
    vfmsub213pd %ymm15, %ymm11, %ymm9
    vfmsub213pd (%rax), %ymm14, %ymm3
    vfmsub213pd 8(%rsp), %ymm3, %ymm8
    vfmsub213pd -200(%rbp), %ymm8, %ymm7
    vfmsub213pd (%r12), %ymm7, %ymm11
    vfmsub213pd 0x40(%r13), %ymm11, %ymm1
    vfmsub213pd (%rax,%r9,8), %ymm1, %ymm14
    vfmsub213pd 16(%r15,%rcx,2), %ymm14, %ymm3
    vfmsub213pd -4(%rdx,%r14,4), %ymm3, %ymm8
    vfmsub231ps %xmm1, %xmm6, %xmm3
    vfmsub231ps %xmm12, %xmm0, %xmm7
    vfmsub231ps %xmm7, %xmm11, %xmm1
    vfmsub231ps %xmm9, %xmm14, %xmm3
    vfmsub231ps %xmm3, %xmm0, %xmm15
    vfmsub231ps %xmm15, %xmm2, %xmm9
    vfmsub231ps %xmm1, %xmm14, %xmm12
    vfmsub231ps %xmm12, %xmm8, %xmm15
    vfmsub231ps (%rax), %xmm14, %xmm3
    vfmsub231ps 8(%rsp), %xmm3, %xmm8
    vfmsub231ps -200(%rbp), %xmm8, %xmm7
    vfmsub231ps (%r12), %xmm7, %xmm11
    vfmsub231ps 0x40(%r13), %xmm11, %xmm1
    vfmsub231ps (%rax,%r9,8), %xmm1, %xmm14
    vfmsub231ps 16(%r15,%rcx,2), %xmm14, %xmm3
    vfmsub231ps -4(%rdx,%r14,4), %xmm3, %xmm8
    vfmsub231ps %ymm7, %ymm2, %ymm1
    vfmsub231ps %ymm9, %ymm6, %ymm3
    vfmsub231ps %ymm3, %ymm8, %ymm7
    vfmsub231ps %ymm15, %ymm11, %ymm1
    vfmsub231ps %ymm1, %ymm6, %ymm12
    vfmsub231ps %ymm12, %ymm0, %ymm15
    vfmsub231ps %ymm7, %ymm11, %ymm9
    vfmsub231ps %ymm9, %ymm14, %ymm12
    vfmsub231ps (%rax), %ymm14, %ymm3
    vfmsub231ps 8(%rsp), %ymm3, %ymm8
    vfmsub231ps -200(%rbp), %ymm8, %ymm7
    vfmsub231ps (%r12), %ymm7, %ymm11
    vfmsub231ps 0x40(%r13), %ymm11, %ymm1
    vfmsub231ps (%rax,%r9,8), %ymm1, %ymm14
    vfmsub231ps 16(%r15,%rcx,2), %ymm14, %ymm3
    vfmsub231ps -4(%rdx,%r14,4), %ymm3, %ymm8
    vfmsub231pd %xmm3, %xmm0, %xmm7
    vfmsub231pd %xmm15, %xmm2, %xmm1
    vfmsub231pd %xmm1, %xmm14, %xmm3
    vfmsub231pd %xmm12, %xmm8, %xmm7
    vfmsub231pd %xmm7, %xmm2, %xmm9
    vfmsub231pd %xmm9, %xmm6, %xmm12
    vfmsub231pd %xmm3, %xmm8, %xmm15
    vfmsub231pd %xmm15, %xmm11, %xmm9
    vfmsub231pd (%rax), %xmm14, %xmm3
    vfmsub231pd 8(%rsp), %xmm3, %xmm8
    vfmsub231pd -200(%rbp), %xmm8, %xmm7
    vfmsub231pd (%r12), %xmm7, %xmm11
    vfmsub231pd 0x40(%r13), %xmm11, %xmm1
    vfmsub231pd (%rax,%r9,8), %xmm1, %xmm14
    vfmsub231pd 16(%r15,%rcx,2), %xmm14, %xmm3
    vfmsub231pd -4(%rdx,%r14,4), %xmm3, %xmm8
    vfmsub231pd %ymm1, %ymm6, %ymm3
    vfmsub231pd %ymm12, %ymm0, %ymm7
    vfmsub231pd %ymm7, %ymm11, %ymm1
    vfmsub231pd %ymm9, %ymm14, %ymm3
    vfmsub231pd %ymm3, %ymm0, %ymm15
    vfmsub231pd %ymm15, %ymm2, %ymm9
    vfmsub231pd %ymm1, %ymm14, %ymm12
    vfmsub231pd %ymm12, %ymm8, %ymm15
    vfmsub231pd (%rax), %ymm14, %ymm3
    vfmsub231pd 8(%rsp), %ymm3, %ymm8
    vfmsub231pd -200(%rbp), %ymm8, %ymm7
    vfmsub231pd (%r12), %ymm7, %ymm11
    vfmsub231pd 0x40(%r13), %ymm11, %ymm1
    vfmsub231pd (%rax,%r9,8), %ymm1, %ymm14
    vfmsub231pd 16(%r15,%rcx,2), %ymm14, %ymm3
    vfmsub231pd -4(%rdx,%r14,4), %ymm3, %ymm8
    vfnmadd132ps %xmm7, %xmm2, %xmm1
    vfnmadd132ps %xmm9, %xmm6, %xmm3
    vfnmadd132ps %xmm3, %xmm8, %xmm7
    vfnmadd132ps %xmm15, %xmm11, %xmm1
    vfnmadd132ps %xmm1, %xmm6, %xmm12
    vfnmadd132ps %xmm12, %xmm0, %xmm15
    vfnmadd132ps %xmm7, %xmm11, %xmm9
    vfnmadd132ps %xmm9, %xmm14, %xmm12
    vfnmadd132ps (%rax), %xmm14, %xmm3
    vfnmadd132ps 8(%rsp), %xmm3, %xmm8
    vfnmadd132ps -200(%rbp), %xmm8, %xmm7
    vfnmadd132ps (%r12), %xmm7, %xmm11
    vfnmadd132ps 0x40(%r13), %xmm11, %xmm1
    vfnmadd132ps (%rax,%r9,8), %xmm1, %xmm14
    vfnmadd132ps 16(%r15,%rcx,2), %xmm14, %xmm3
    vfnmadd132ps -4(%rdx,%r14,4), %xmm3, %xmm8
    vfnmadd132ps %ymm3, %ymm0, %ymm7
    vfnmadd132ps %ymm15, %ymm2, %ymm1
    vfnmadd132ps %ymm1, %ymm14, %ymm3
    vfnmadd132ps %ymm12, %ymm8, %ymm7
    vfnmadd132ps %ymm7, %ymm2, %ymm9
    vfnmadd132ps %ymm9, %ymm6, %ymm12
    vfnmadd132ps %ymm3, %ymm8, %ymm15
    vfnmadd132ps %ymm15, %ymm11, %ymm9
    vfnmadd132ps (%rax), %ymm14, %ymm3
    vfnmadd132ps 8(%rsp), %ymm3, %ymm8
    vfnmadd132ps -200(%rbp), %ymm8, %ymm7
    vfnmadd132ps (%r12), %ymm7, %ymm11
    vfnmadd132ps 0x40(%r13), %ymm11, %ymm1
    vfnmadd132ps (%rax,%r9,8), %ymm1, %ymm14
    vfnmadd132ps 16(%r15,%rcx,2), %ymm14, %ymm3
    vfnmadd132ps -4(%rdx,%r14,4), %ymm3, %ymm8
    vfnmadd132pd %xmm1, %xmm6, %xmm3
    vfnmadd132pd %xmm12, %xmm0, %xmm7
    vfnmadd132pd %xmm7, %xmm11, %xmm1
    vfnmadd132pd %xmm9, %xmm14, %xmm3
    vfnmadd132pd %xmm3, %xmm0, %xmm15
    vfnmadd132pd %xmm15, %xmm2, %xmm9
    vfnmadd132pd %xmm1, %xmm14, %xmm12
    vfnmadd132pd %xmm12, %xmm8, %xmm15
    vfnmadd132pd (%rax), %xmm14, %xmm3
    vfnmadd132pd 8(%rsp), %xmm3, %xmm8
    vfnmadd132pd -200(%rbp), %xmm8, %xmm7
    vfnmadd132pd (%r12), %xmm7, %xmm11
    vfnmadd132pd 0x40(%r13), %xmm11, %xmm1
    vfnmadd132pd (%rax,%r9,8), %xmm1, %xmm14
    vfnmadd132pd 16(%r15,%rcx,2), %xmm14, %xmm3
    vfnmadd132pd -4(%rdx,%r14,4), %xmm3, %xmm8
    vfnmadd132pd %ymm7, %ymm2, %ymm1
    vfnmadd132pd %ymm9, %ymm6, %ymm3
    vfnmadd132pd %ymm3, %ymm8, %ymm7
    vfnmadd132pd %ymm15, %ymm11, %ymm1
    vfnmadd132pd %ymm1, %ymm6, %ymm12
    vfnmadd132pd %ymm12, %ymm0, %ymm15
    vfnmadd132pd %ymm7, %ymm11, %ymm9
    vfnmadd132pd %ymm9, %ymm14, %ymm12
    vfnmadd132pd (%rax), %ymm14, %ymm3
    vfnmadd132pd 8(%rsp), %ymm3, %ymm8
    vfnmadd132pd -200(%rbp), %ymm8, %ymm7
    vfnmadd132pd (%r12), %ymm7, %ymm11
    vfnmadd132pd 0x40(%r13), %ymm11, %ymm1
    vfnmadd132pd (%rax,%r9,8), %ymm1, %ymm14
    vfnmadd132pd 16(%r15,%rcx,2), %ymm14, %ymm3
    vfnmadd132pd -4(%rdx,%r14,4), %ymm3, %ymm8
    vfnmadd213ps %xmm3, %xmm0, %xmm7
    vfnmadd213ps %xmm15, %xmm2, %xmm1
    vfnmadd213ps %xmm1, %xmm14, %xmm3
    vfnmadd213ps %xmm12, %xmm8, %xmm7
    vfnmadd213ps %xmm7, %xmm2, %xmm9
    vfnmadd213ps %xmm9, %xmm6, %xmm12
    vfnmadd213ps %xmm3, %xmm8, %xmm15
    vfnmadd213ps %xmm15, %xmm11, %xmm9
    vfnmadd213ps (%rax), %xmm14, %xmm3
    vfnmadd213ps 8(%rsp), %xmm3, %xmm8
    vfnmadd213ps -200(%rbp), %xmm8, %xmm7
    vfnmadd213ps (%r12), %xmm7, %xmm11
    vfnmadd213ps 0x40(%r13), %xmm11, %xmm1
    vfnmadd213ps (%rax,%r9,8), %xmm1, %xmm14
    vfnmadd213ps 16(%r15,%rcx,2), %xmm14, %xmm3
    vfnmadd213ps -4(%rdx,%r14,4), %xmm3, %xmm8
    vfnmadd213ps %ymm1, %ymm6, %ymm3
    vfnmadd213ps %ymm12, %ymm0, %ymm7
    vfnmadd213ps %ymm7, %ymm11, %ymm1
    vfnmadd213ps %ymm9, %ymm14, %ymm3
    vfnmadd213ps %ymm3, %ymm0, %ymm15
    vfnmadd213ps %ymm15, %ymm2, %ymm9
    vfnmadd213ps %ymm1, %ymm14, %ymm12
    vfnmadd213ps %ymm12, %ymm8, %ymm15
    vfnmadd213ps (%rax), %ymm14, %ymm3
    vfnmadd213ps 8(%rsp), %ymm3, %ymm8
    vfnmadd213ps -200(%rbp), %ymm8, %ymm7
    vfnmadd213ps (%r12), %ymm7, %ymm11
    vfnmadd213ps 0x40(%r13), %ymm11, %ymm1
    vfnmadd213ps (%rax,%r9,8), %ymm1, %ymm14
    vfnmadd213ps 16(%r15,%rcx,2), %ymm14, %ymm3
    vfnmadd213ps -4(%rdx,%r14,4), %ymm3, %ymm8
    vfnmadd213pd %xmm7, %xmm2, %xmm1
    vfnmadd213pd %xmm9, %xmm6, %xmm3
    vfnmadd213pd %xmm3, %xmm8, %xmm7
    vfnmadd213pd %xmm15, %xmm11, %xmm1
    vfnmadd213pd %xmm1, %xmm6, %xmm12
    vfnmadd213pd %xmm12, %xmm0, %xmm15
    vfnmadd213pd %xmm7, %xmm11, %xmm9
    vfnmadd213pd %xmm9, %xmm14, %xmm12
    vfnmadd213pd (%rax), %xmm14, %xmm3
    vfnmadd213pd 8(%rsp), %xmm3, %xmm8
    vfnmadd213pd -200(%rbp), %xmm8, %xmm7
    vfnmadd213pd (%r12), %xmm7, %xmm11
    vfnmadd213pd 0x40(%r13), %xmm11, %xmm1
    vfnmadd213pd (%rax,%r9,8), %xmm1, %xmm14
    vfnmadd213pd 16(%r15,%rcx,2), %xmm14, %xmm3
    vfnmadd213pd -4(%rdx,%r14,4), %xmm3, %xmm8
    vfnmadd213pd %ymm3, %ymm0, %ymm7
    vfnmadd213pd %ymm15, %ymm2, %ymm1
    vfnmadd213pd %ymm1, %ymm14, %ymm3
    vfnmadd213pd %ymm12, %ymm8, %ymm7
    vfnmadd213pd %ymm7, %ymm2, %ymm9
    vfnmadd213pd %ymm9, %ymm6, %ymm12
    vfnmadd213pd %ymm3, %ymm8, %ymm15
    vfnmadd213pd %ymm15, %ymm11, %ymm9
    vfnmadd213pd (%rax), %ymm14, %ymm3
    vfnmadd213pd 8(%rsp), %ymm3, %ymm8
    vfnmadd213pd -200(%rbp), %ymm8, %ymm7
    vfnmadd213pd (%r12), %ymm7, %ymm11
    vfnmadd213pd 0x40(%r13), %ymm11, %ymm1
    vfnmadd213pd (%rax,%r9,8), %ymm1, %ymm14
    vfnmadd213pd 16(%r15,%rcx,2), %ymm14, %ymm3
    vfnmadd213pd -4(%rdx,%r14,4), %ymm3, %ymm8
    vfnmadd231ps %xmm1, %xmm6, %xmm3
    vfnmadd231ps %xmm12, %xmm0, %xmm7
    vfnmadd231ps %xmm7, %xmm11, %xmm1
    vfnmadd231ps %xmm9, %xmm14, %xmm3
    vfnmadd231ps %xmm3, %xmm0, %xmm15
    vfnmadd231ps %xmm15, %xmm2, %xmm9
    vfnmadd231ps %xmm1, %xmm14, %xmm12
    vfnmadd231ps %xmm12, %xmm8, %xmm15
    vfnmadd231ps (%rax), %xmm14, %xmm3
    vfnmadd231ps 8(%rsp), %xmm3, %xmm8
    vfnmadd231ps -200(%rbp), %xmm8, %xmm7
    vfnmadd231ps (%r12), %xmm7, %xmm11
    vfnmadd231ps 0x40(%r13), %xmm11, %xmm1
    vfnmadd231ps (%rax,%r9,8), %xmm1, %xmm14
    vfnmadd231ps 16(%r15,%rcx,2), %xmm14, %xmm3
    vfnmadd231ps -4(%rdx,%r14,4), %xmm3, %xmm8
    vfnmadd231ps %ymm7, %ymm2, %ymm1
    vfnmadd231ps %ymm9, %ymm6, %ymm3
    vfnmadd231ps %ymm3, %ymm8, %ymm7
    vfnmadd231ps %ymm15, %ymm11, %ymm1
    vfnmadd231ps %ymm1, %ymm6, %ymm12
    vfnmadd231ps %ymm12, %ymm0, %ymm15
    vfnmadd231ps %ymm7, %ymm11, %ymm9
    vfnmadd231ps %ymm9, %ymm14, %ymm12
    vfnmadd231ps (%rax), %ymm14, %ymm3
    vfnmadd231ps 8(%rsp), %ymm3, %ymm8
    vfnmadd231ps -200(%rbp), %ymm8, %ymm7
    vfnmadd231ps (%r12), %ymm7, %ymm11
    vfnmadd231ps 0x40(%r13), %ymm11, %ymm1
    vfnmadd231ps (%rax,%r9,8), %ymm1, %ymm14
    vfnmadd231ps 16(%r15,%rcx,2), %ymm14, %ymm3
    vfnmadd231ps -4(%rdx,%r14,4), %ymm3, %ymm8
    vfnmadd231pd %xmm3, %xmm0, %xmm7
    vfnmadd231pd %xmm15, %xmm2, %xmm1
    vfnmadd231pd %xmm1, %xmm14, %xmm3
    vfnmadd231pd %xmm12, %xmm8, %xmm7
    vfnmadd231pd %xmm7, %xmm2, %xmm9
    vfnmadd231pd %xmm9, %xmm6, %xmm12
    vfnmadd231pd %xmm3, %xmm8, %xmm15
    vfnmadd231pd %xmm15, %xmm11, %xmm9
    vfnmadd231pd (%rax), %xmm14, %xmm3
    vfnmadd231pd 8(%rsp), %xmm3, %xmm8
    vfnmadd231pd -200(%rbp), %xmm8, %xmm7
    vfnmadd231pd (%r12), %xmm7, %xmm11
    vfnmadd231pd 0x40(%r13), %xmm11, %xmm1
    vfnmadd231pd (%rax,%r9,8), %xmm1, %xmm14
    vfnmadd231pd 16(%r15,%rcx,2), %xmm14, %xmm3
    vfnmadd231pd -4(%rdx,%r14,4), %xmm3, %xmm8
    vfnmadd231pd %ymm1, %ymm6, %ymm3
    vfnmadd231pd %ymm12, %ymm0, %ymm7
    vfnmadd231pd %ymm7, %ymm11, %ymm1
    vfnmadd231pd %ymm9, %ymm14, %ymm3
    vfnmadd231pd %ymm3, %ymm0, %ymm15
    vfnmadd231pd %ymm15, %ymm2, %ymm9
    vfnmadd231pd %ymm1, %ymm14, %ymm12
    vfnmadd231pd %ymm12, %ymm8, %ymm15
    vfnmadd231pd (%rax), %ymm14, %ymm3
    vfnmadd231pd 8(%rsp), %ymm3, %ymm8
    vfnmadd231pd -200(%rbp), %ymm8, %ymm7
    vfnmadd231pd (%r12), %ymm7, %ymm11
    vfnmadd231pd 0x40(%r13), %ymm11, %ymm1
    vfnmadd231pd (%rax,%r9,8), %ymm1, %ymm14
    vfnmadd231pd 16(%r15,%rcx,2), %ymm14, %ymm3
    vfnmadd231pd -4(%rdx,%r14,4), %ymm3, %ymm8
    vfnmsub132ps %xmm7, %xmm2, %xmm1
    vfnmsub132ps %xmm9, %xmm6, %xmm3
    vfnmsub132ps %xmm3, %xmm8, %xmm7
    vfnmsub132ps %xmm15, %xmm11, %xmm1
    vfnmsub132ps %xmm1, %xmm6, %xmm12
    vfnmsub132ps %xmm12, %xmm0, %xmm15
    vfnmsub132ps %xmm7, %xmm11, %xmm9
    vfnmsub132ps %xmm9, %xmm14, %xmm12
    vfnmsub132ps (%rax), %xmm14, %xmm3
    vfnmsub132ps 8(%rsp), %xmm3, %xmm8
    vfnmsub132ps -200(%rbp), %xmm8, %xmm7
    vfnmsub132ps (%r12), %xmm7, %xmm11
    vfnmsub132ps 0x40(%r13), %xmm11, %xmm1
    vfnmsub132ps (%rax,%r9,8), %xmm1, %xmm14
    vfnmsub132ps 16(%r15,%rcx,2), %xmm14, %xmm3
    vfnmsub132ps -4(%rdx,%r14,4), %xmm3, %xmm8
    vfnmsub132ps %ymm3, %ymm0, %ymm7
    vfnmsub132ps %ymm15, %ymm2, %ymm1
    vfnmsub132ps %ymm1, %ymm14, %ymm3
    vfnmsub132ps %ymm12, %ymm8, %ymm7
    vfnmsub132ps %ymm7, %ymm2, %ymm9
    vfnmsub132ps %ymm9, %ymm6, %ymm12
    vfnmsub132ps %ymm3, %ymm8, %ymm15
    vfnmsub132ps %ymm15, %ymm11, %ymm9
    vfnmsub132ps (%rax), %ymm14, %ymm3
    vfnmsub132ps 8(%rsp), %ymm3, %ymm8
    vfnmsub132ps -200(%rbp), %ymm8, %ymm7
    vfnmsub132ps (%r12), %ymm7, %ymm11
    vfnmsub132ps 0x40(%r13), %ymm11, %ymm1
    vfnmsub132ps (%rax,%r9,8), %ymm1, %ymm14
    vfnmsub132ps 16(%r15,%rcx,2), %ymm14, %ymm3
    vfnmsub132ps -4(%rdx,%r14,4), %ymm3, %ymm8
    vfnmsub132pd %xmm1, %xmm6, %xmm3
    vfnmsub132pd %xmm12, %xmm0, %xmm7
    vfnmsub132pd %xmm7, %xmm11, %xmm1
    vfnmsub132pd %xmm9, %xmm14, %xmm3
    vfnmsub132pd %xmm3, %xmm0, %xmm15
    vfnmsub132pd %xmm15, %xmm2, %xmm9
    vfnmsub132pd %xmm1, %xmm14, %xmm12
    vfnmsub132pd %xmm12, %xmm8, %xmm15
    vfnmsub132pd (%rax), %xmm14, %xmm3
    vfnmsub132pd 8(%rsp), %xmm3, %xmm8
    vfnmsub132pd -200(%rbp), %xmm8, %xmm7
    vfnmsub132pd (%r12), %xmm7, %xmm11
    vfnmsub132pd 0x40(%r13), %xmm11, %xmm1
    vfnmsub132pd (%rax,%r9,8), %xmm1, %xmm14
    vfnmsub132pd 16(%r15,%rcx,2), %xmm14, %xmm3
    vfnmsub132pd -4(%rdx,%r14,4), %xmm3, %xmm8
    vfnmsub132pd %ymm7, %ymm2, %ymm1
    vfnmsub132pd %ymm9, %ymm6, %ymm3
    vfnmsub132pd %ymm3, %ymm8, %ymm7
    vfnmsub132pd %ymm15, %ymm11, %ymm1
    vfnmsub132pd %ymm1, %ymm6, %ymm12
    vfnmsub132pd %ymm12, %ymm0, %ymm15
    vfnmsub132pd %ymm7, %ymm11, %ymm9
    vfnmsub132pd %ymm9, %ymm14, %ymm12
    vfnmsub132pd (%rax), %ymm14, %ymm3
    vfnmsub132pd 8(%rsp), %ymm3, %ymm8
    vfnmsub132pd -200(%rbp), %ymm8, %ymm7
    vfnmsub132pd (%r12), %ymm7, %ymm11
    vfnmsub132pd 0x40(%r13), %ymm11, %ymm1
    vfnmsub132pd (%rax,%r9,8), %ymm1, %ymm14
    vfnmsub132pd 16(%r15,%rcx,2), %ymm14, %ymm3
    vfnmsub132pd -4(%rdx,%r14,4), %ymm3, %ymm8
    vfnmsub213ps %xmm3, %xmm0, %xmm7
    vfnmsub213ps %xmm15, %xmm2, %xmm1
    vfnmsub213ps %xmm1, %xmm14, %xmm3
    vfnmsub213ps %xmm12, %xmm8, %xmm7
    vfnmsub213ps %xmm7, %xmm2, %xmm9
    vfnmsub213ps %xmm9, %xmm6, %xmm12
    vfnmsub213ps %xmm3, %xmm8, %xmm15
    vfnmsub213ps %xmm15, %xmm11, %xmm9
    vfnmsub213ps (%rax), %xmm14, %xmm3
    vfnmsub213ps 8(%rsp), %xmm3, %xmm8
    vfnmsub213ps -200(%rbp), %xmm8, %xmm7
    vfnmsub213ps (%r12), %xmm7, %xmm11
    vfnmsub213ps 0x40(%r13), %xmm11, %xmm1
    vfnmsub213ps (%rax,%r9,8), %xmm1, %xmm14
    vfnmsub213ps 16(%r15,%rcx,2), %xmm14, %xmm3
    vfnmsub213ps -4(%rdx,%r14,4), %xmm3, %xmm8
    vfnmsub213ps %ymm1, %ymm6, %ymm3
    vfnmsub213ps %ymm12, %ymm0, %ymm7
    vfnmsub213ps %ymm7, %ymm11, %ymm1
    vfnmsub213ps %ymm9, %ymm14, %ymm3
    vfnmsub213ps %ymm3, %ymm0, %ymm15
    vfnmsub213ps %ymm15, %ymm2, %ymm9
    vfnmsub213ps %ymm1, %ymm14, %ymm12
    vfnmsub213ps %ymm12, %ymm8, %ymm15
    vfnmsub213ps (%rax), %ymm14, %ymm3
    vfnmsub213ps 8(%rsp), %ymm3, %ymm8
    vfnmsub213ps -200(%rbp), %ymm8, %ymm7
    vfnmsub213ps (%r12), %ymm7, %ymm11
    vfnmsub213ps 0x40(%r13), %ymm11, %ymm1
    vfnmsub213ps (%rax,%r9,8), %ymm1, %ymm14
    vfnmsub213ps 16(%r15,%rcx,2), %ymm14, %ymm3
    vfnmsub213ps -4(%rdx,%r14,4), %ymm3, %ymm8
    vfnmsub213pd %xmm7, %xmm2, %xmm1
    vfnmsub213pd %xmm9, %xmm6, %xmm3
    vfnmsub213pd %xmm3, %xmm8, %xmm7
    vfnmsub213pd %xmm15, %xmm11, %xmm1
    vfnmsub213pd %xmm1, %xmm6, %xmm12
    vfnmsub213pd %xmm12, %xmm0, %xmm15
    vfnmsub213pd %xmm7, %xmm11, %xmm9
    vfnmsub213pd %xmm9, %xmm14, %xmm12
    vfnmsub213pd (%rax), %xmm14, %xmm3
    vfnmsub213pd 8(%rsp), %xmm3, %xmm8
    vfnmsub213pd -200(%rbp), %xmm8, %xmm7
    vfnmsub213pd (%r12), %xmm7, %xmm11
    vfnmsub213pd 0x40(%r13), %xmm11, %xmm1
    vfnmsub213pd (%rax,%r9,8), %xmm1, %xmm14
    vfnmsub213pd 16(%r15,%rcx,2), %xmm14, %xmm3
    vfnmsub213pd -4(%rdx,%r14,4), %xmm3, %xmm8
    vfnmsub213pd %ymm3, %ymm0, %ymm7
    vfnmsub213pd %ymm15, %ymm2, %ymm1
    vfnmsub213pd %ymm1, %ymm14, %ymm3
    vfnmsub213pd %ymm12, %ymm8, %ymm7
    vfnmsub213pd %ymm7, %ymm2, %ymm9
    vfnmsub213pd %ymm9, %ymm6, %ymm12
    vfnmsub213pd %ymm3, %ymm8, %ymm15
    vfnmsub213pd %ymm15, %ymm11, %ymm9
    vfnmsub213pd (%rax), %ymm14, %ymm3
    vfnmsub213pd 8(%rsp), %ymm3, %ymm8
    vfnmsub213pd -200(%rbp), %ymm8, %ymm7
    vfnmsub213pd (%r12), %ymm7, %ymm11
    vfnmsub213pd 0x40(%r13), %ymm11, %ymm1
    vfnmsub213pd (%rax,%r9,8), %ymm1, %ymm14
    vfnmsub213pd 16(%r15,%rcx,2), %ymm14, %ymm3
    vfnmsub213pd -4(%rdx,%r14,4), %ymm3, %ymm8
    vfnmsub231ps %xmm1, %xmm6, %xmm3
    vfnmsub231ps %xmm12, %xmm0, %xmm7
    vfnmsub231ps %xmm7, %xmm11, %xmm1
    vfnmsub231ps %xmm9, %xmm14, %xmm3
    vfnmsub231ps %xmm3, %xmm0, %xmm15
    vfnmsub231ps %xmm15, %xmm2, %xmm9
    vfnmsub231ps %xmm1, %xmm14, %xmm12
    vfnmsub231ps %xmm12, %xmm8, %xmm15
    vfnmsub231ps (%rax), %xmm14, %xmm3
    vfnmsub231ps 8(%rsp), %xmm3, %xmm8
    vfnmsub231ps -200(%rbp), %xmm8, %xmm7
    vfnmsub231ps (%r12), %xmm7, %xmm11
    vfnmsub231ps 0x40(%r13), %xmm11, %xmm1
    vfnmsub231ps (%rax,%r9,8), %xmm1, %xmm14
    vfnmsub231ps 16(%r15,%rcx,2), %xmm14, %xmm3
    vfnmsub231ps -4(%rdx,%r14,4), %xmm3, %xmm8
    vfnmsub231ps %ymm7, %ymm2, %ymm1
    vfnmsub231ps %ymm9, %ymm6, %ymm3
    vfnmsub231ps %ymm3, %ymm8, %ymm7
    vfnmsub231ps %ymm15, %ymm11, %ymm1
    vfnmsub231ps %ymm1, %ymm6, %ymm12
    vfnmsub231ps %ymm12, %ymm0, %ymm15
    vfnmsub231ps %ymm7, %ymm11, %ymm9
    vfnmsub231ps %ymm9, %ymm14, %ymm12
    vfnmsub231ps (%rax), %ymm14, %ymm3
    vfnmsub231ps 8(%rsp), %ymm3, %ymm8
    vfnmsub231ps -200(%rbp), %ymm8, %ymm7
    vfnmsub231ps (%r12), %ymm7, %ymm11
    vfnmsub231ps 0x40(%r13), %ymm11, %ymm1
    vfnmsub231ps (%rax,%r9,8), %ymm1, %ymm14
    vfnmsub231ps 16(%r15,%rcx,2), %ymm14, %ymm3
    vfnmsub231ps -4(%rdx,%r14,4), %ymm3, %ymm8
    vfnmsub231pd %xmm3, %xmm0, %xmm7
    vfnmsub231pd %xmm15, %xmm2, %xmm1
    vfnmsub231pd %xmm1, %xmm14, %xmm3
    vfnmsub231pd %xmm12, %xmm8, %xmm7
    vfnmsub231pd %xmm7, %xmm2, %xmm9
    vfnmsub231pd %xmm9, %xmm6, %xmm12
    vfnmsub231pd %xmm3, %xmm8, %xmm15
    vfnmsub231pd %xmm15, %xmm11, %xmm9
    vfnmsub231pd (%rax), %xmm14, %xmm3
    vfnmsub231pd 8(%rsp), %xmm3, %xmm8
    vfnmsub231pd -200(%rbp), %xmm8, %xmm7
    vfnmsub231pd (%r12), %xmm7, %xmm11
    vfnmsub231pd 0x40(%r13), %xmm11, %xmm1
    vfnmsub231pd (%rax,%r9,8), %xmm1, %xmm14
    vfnmsub231pd 16(%r15,%rcx,2), %xmm14, %xmm3
    vfnmsub231pd -4(%rdx,%r14,4), %xmm3, %xmm8
    vfnmsub231pd %ymm1, %ymm6, %ymm3
    vfnmsub231pd %ymm12, %ymm0, %ymm7
    vfnmsub231pd %ymm7, %ymm11, %ymm1
    vfnmsub231pd %ymm9, %ymm14, %ymm3
    vfnmsub231pd %ymm3, %ymm0, %ymm15
    vfnmsub231pd %ymm15, %ymm2, %ymm9
    vfnmsub231pd %ymm1, %ymm14, %ymm12
    vfnmsub231pd %ymm12, %ymm8, %ymm15
    vfnmsub231pd (%rax), %ymm14, %ymm3
    vfnmsub231pd 8(%rsp), %ymm3, %ymm8
    vfnmsub231pd -200(%rbp), %ymm8, %ymm7
    vfnmsub231pd (%r12), %ymm7, %ymm11
    vfnmsub231pd 0x40(%r13), %ymm11, %ymm1
    vfnmsub231pd (%rax,%r9,8), %ymm1, %ymm14
    vfnmsub231pd 16(%r15,%rcx,2), %ymm14, %ymm3
    vfnmsub231pd -4(%rdx,%r14,4), %ymm3, %ymm8
    andnl %edi, %edx, %ecx
    andnl %r9d, %esi, %ebx
    andnl %ebx, %r8d, %edi
    andnl %r15d, %r11d, %ecx
    andnl %ecx, %esi, %r12d
    andnl %r12d, %eax, %r15d
    andnl %edi, %r11d, %r9d
    andnl %r9d, %r14d, %r12d
    andnl (%rax), %r14d, %ebx
    andnl 8(%rsp), %ebx, %r8d
    andnl -200(%rbp), %r8d, %edi
    andnl (%r12), %edi, %r11d
    andnl 0x40(%r13), %r11d, %ecx
    andnl (%rax,%r9,8), %ecx, %r14d
    andnl 16(%r15,%rcx,2), %r14d, %ebx
    andnl -4(%rdx,%r14,4), %ebx, %r8d
    bextrl %ebx, %eax, %edi
    bextrl %r15d, %edx, %ecx
    bextrl %ecx, %r14d, %ebx
    bextrl %r12d, %r8d, %edi
    bextrl %edi, %edx, %r9d
    bextrl %r9d, %esi, %r12d
    bextrl %ebx, %r8d, %r15d
    bextrl %r15d, %r11d, %r9d
    bextrl %ecx, (%rax), %ebx
    bextrl %r14d, 8(%rsp), %r8d
    bextrl %ebx, -200(%rbp), %edi
    bextrl %r8d, (%r12), %r11d
    bextrl %edi, 0x40(%r13), %ecx
    bextrl %r11d, (%rax,%r9,8), %r14d
    bextrl %ecx, 16(%r15,%rcx,2), %ebx
    bextrl %r14d, -4(%rdx,%r14,4), %r8d
    bzhil %ecx, %esi, %ebx
    bzhil %r12d, %eax, %edi
    bzhil %edi, %r11d, %ecx
    bzhil %r9d, %r14d, %ebx
    bzhil %ebx, %eax, %r15d
    bzhil %r15d, %edx, %r9d
    bzhil %ecx, %r14d, %r12d
    bzhil %r12d, %r8d, %r15d
    bzhil %ecx, (%rax), %ebx
    bzhil %r14d, 8(%rsp), %r8d
    bzhil %ebx, -200(%rbp), %edi
    bzhil %r8d, (%r12), %r11d
    bzhil %edi, 0x40(%r13), %ecx
    bzhil %r11d, (%rax,%r9,8), %r14d
    bzhil %ecx, 16(%r15,%rcx,2), %ebx
    bzhil %r14d, -4(%rdx,%r14,4), %r8d
    pdepl %edi, %edx, %ecx
    pdepl %r9d, %esi, %ebx
    pdepl %ebx, %r8d, %edi
    pdepl %r15d, %r11d, %ecx
    pdepl %ecx, %esi, %r12d
    pdepl %r12d, %eax, %r15d
    pdepl %edi, %r11d, %r9d
    pdepl %r9d, %r14d, %r12d
    pdepl (%rax), %r14d, %ebx
    pdepl 8(%rsp), %ebx, %r8d
    pdepl -200(%rbp), %r8d, %edi
    pdepl (%r12), %edi, %r11d
    pdepl 0x40(%r13), %r11d, %ecx
    pdepl (%rax,%r9,8), %ecx, %r14d
    pdepl 16(%r15,%rcx,2), %r14d, %ebx
    pdepl -4(%rdx,%r14,4), %ebx, %r8d
    pextl %ebx, %eax, %edi
    pextl %r15d, %edx, %ecx
    pextl %ecx, %r14d, %ebx
    pextl %r12d, %r8d, %edi
    pextl %edi, %edx, %r9d
    pextl %r9d, %esi, %r12d
    pextl %ebx, %r8d, %r15d
    pextl %r15d, %r11d, %r9d
    pextl (%rax), %r14d, %ebx
    pextl 8(%rsp), %ebx, %r8d
    pextl -200(%rbp), %r8d, %edi
    pextl (%r12), %edi, %r11d
    pextl 0x40(%r13), %r11d, %ecx
    pextl (%rax,%r9,8), %ecx, %r14d
    pextl 16(%r15,%rcx,2), %r14d, %ebx
    pextl -4(%rdx,%r14,4), %ebx, %r8d
    blsrl %ecx, %esi
    blsrl %r12d, %eax
    blsrl %edi, %r11d
    blsrl %r9d, %r14d
    blsrl (%rax), %r14d
    blsrl 8(%rsp), %ebx
    blsrl -200(%rbp), %r8d
    blsrl (%r12), %edi
    blsrl 0x40(%r13), %r11d
    blsrl (%rax,%r9,8), %ecx
    blsrl 16(%r15,%rcx,2), %r14d
    blsrl -4(%rdx,%r14,4), %ebx
    blsmskl %ecx, %esi
    blsmskl %r12d, %eax
    blsmskl %edi, %r11d
    blsmskl %r9d, %r14d
    blsmskl (%rax), %r14d
    blsmskl 8(%rsp), %ebx
    blsmskl -200(%rbp), %r8d
    blsmskl (%r12), %edi
    blsmskl 0x40(%r13), %r11d
    blsmskl (%rax,%r9,8), %ecx
    blsmskl 16(%r15,%rcx,2), %r14d
    blsmskl -4(%rdx,%r14,4), %ebx
    blsil %ecx, %esi
    blsil %r12d, %eax
    blsil %edi, %r11d
    blsil %r9d, %r14d
    blsil (%rax), %r14d
    blsil 8(%rsp), %ebx
    blsil -200(%rbp), %r8d
    blsil (%r12), %edi
    blsil 0x40(%r13), %r11d
    blsil (%rax,%r9,8), %ecx
    blsil 16(%r15,%rcx,2), %r14d
    blsil -4(%rdx,%r14,4), %ebx
    andnq %rcx, %rsi, %rbx
    andnq %r12, %rax, %rdi
    andnq %rdi, %r11, %rcx
    andnq %r9, %r14, %rbx
    andnq %rbx, %rax, %r15
    andnq %r15, %rdx, %r9
    andnq %rcx, %r14, %r12
    andnq %r12, %r8, %r15
    andnq (%rax), %r14, %rbx
    andnq 8(%rsp), %rbx, %r8
    andnq -200(%rbp), %r8, %rdi
    andnq (%r12), %rdi, %r11
    andnq 0x40(%r13), %r11, %rcx
    andnq (%rax,%r9,8), %rcx, %r14
    andnq 16(%r15,%rcx,2), %r14, %rbx
    andnq -4(%rdx,%r14,4), %rbx, %r8
    bextrq %rdi, %rdx, %rcx
    bextrq %r9, %rsi, %rbx
    bextrq %rbx, %r8, %rdi
    bextrq %r15, %r11, %rcx
    bextrq %rcx, %rsi, %r12
    bextrq %r12, %rax, %r15
    bextrq %rdi, %r11, %r9
    bextrq %r9, %r14, %r12
    bextrq %rcx, (%rax), %rbx
    bextrq %r14, 8(%rsp), %r8
    bextrq %rbx, -200(%rbp), %rdi
    bextrq %r8, (%r12), %r11
    bextrq %rdi, 0x40(%r13), %rcx
    bextrq %r11, (%rax,%r9,8), %r14
    bextrq %rcx, 16(%r15,%rcx,2), %rbx
    bextrq %r14, -4(%rdx,%r14,4), %r8
    bzhiq %rbx, %rax, %rdi
    bzhiq %r15, %rdx, %rcx
    bzhiq %rcx, %r14, %rbx
    bzhiq %r12, %r8, %rdi
    bzhiq %rdi, %rdx, %r9
    bzhiq %r9, %rsi, %r12
    bzhiq %rbx, %r8, %r15
    bzhiq %r15, %r11, %r9
    bzhiq %rcx, (%rax), %rbx
    bzhiq %r14, 8(%rsp), %r8
    bzhiq %rbx, -200(%rbp), %rdi
    bzhiq %r8, (%r12), %r11
    bzhiq %rdi, 0x40(%r13), %rcx
    bzhiq %r11, (%rax,%r9,8), %r14
    bzhiq %rcx, 16(%r15,%rcx,2), %rbx
    bzhiq %r14, -4(%rdx,%r14,4), %r8
    pdepq %rcx, %rsi, %rbx
    pdepq %r12, %rax, %rdi
    pdepq %rdi, %r11, %rcx
    pdepq %r9, %r14, %rbx
    pdepq %rbx, %rax, %r15
    pdepq %r15, %rdx, %r9
    pdepq %rcx, %r14, %r12
    pdepq %r12, %r8, %r15
    pdepq (%rax), %r14, %rbx
    pdepq 8(%rsp), %rbx, %r8
    pdepq -200(%rbp), %r8, %rdi
    pdepq (%r12), %rdi, %r11
    pdepq 0x40(%r13), %r11, %rcx
    pdepq (%rax,%r9,8), %rcx, %r14
    pdepq 16(%r15,%rcx,2), %r14, %rbx
    pdepq -4(%rdx,%r14,4), %rbx, %r8
    pextq %rdi, %rdx, %rcx
    pextq %r9, %rsi, %rbx
    pextq %rbx, %r8, %rdi
    pextq %r15, %r11, %rcx
    pextq %rcx, %rsi, %r12
    pextq %r12, %rax, %r15
    pextq %rdi, %r11, %r9
    pextq %r9, %r14, %r12
    pextq (%rax), %r14, %rbx
    pextq 8(%rsp), %rbx, %r8
    pextq -200(%rbp), %r8, %rdi
    pextq (%r12), %rdi, %r11
    pextq 0x40(%r13), %r11, %rcx
    pextq (%rax,%r9,8), %rcx, %r14
    pextq 16(%r15,%rcx,2), %r14, %rbx
    pextq -4(%rdx,%r14,4), %rbx, %r8
    blsrq %rbx, %rax
    blsrq %r15, %rdx
    blsrq %rcx, %r14
    blsrq %r12, %r8
    blsrq (%rax), %r14
    blsrq 8(%rsp), %rbx
    blsrq -200(%rbp), %r8
    blsrq (%r12), %rdi
    blsrq 0x40(%r13), %r11
    blsrq (%rax,%r9,8), %rcx
    blsrq 16(%r15,%rcx,2), %r14
    blsrq -4(%rdx,%r14,4), %rbx
    blsmskq %rbx, %rax
    blsmskq %r15, %rdx
    blsmskq %rcx, %r14
    blsmskq %r12, %r8
    blsmskq (%rax), %r14
    blsmskq 8(%rsp), %rbx
    blsmskq -200(%rbp), %r8
    blsmskq (%r12), %rdi
    blsmskq 0x40(%r13), %r11
    blsmskq (%rax,%r9,8), %rcx
    blsmskq 16(%r15,%rcx,2), %r14
    blsmskq -4(%rdx,%r14,4), %rbx
    blsiq %rbx, %rax
    blsiq %r15, %rdx
    blsiq %rcx, %r14
    blsiq %r12, %r8
    blsiq (%rax), %r14
    blsiq 8(%rsp), %rbx
    blsiq -200(%rbp), %r8
    blsiq (%r12), %rdi
    blsiq 0x40(%r13), %r11
    blsiq (%rax,%r9,8), %rcx
    blsiq 16(%r15,%rcx,2), %r14
    blsiq -4(%rdx,%r14,4), %rbx
    vmovdqu %ymm3, %ymm0
    vmovdqu %ymm15, %ymm2
    vmovdqu %ymm1, %ymm14
    vmovdqu %ymm12, %ymm8
    vmovdqu (%rax), %ymm14
    vmovdqu 8(%rsp), %ymm3
    vmovdqu -200(%rbp), %ymm8
    vmovdqu (%r12), %ymm7
    vmovdqu 0x40(%r13), %ymm11
    vmovdqu (%rax,%r9,8), %ymm1
    vmovdqu 16(%r15,%rcx,2), %ymm14
    vmovdqu -4(%rdx,%r14,4), %ymm3
    vmovdqu %ymm3, %ymm0
    vmovdqu %ymm15, %ymm2
    vmovdqu %ymm1, %ymm14
    vmovdqu %ymm12, %ymm8
    vmovdqu %ymm1, (%rax)
    vmovdqu %ymm14, 8(%rsp)
    vmovdqu %ymm3, -200(%rbp)
    vmovdqu %ymm8, (%r12)
    vmovdqu %ymm7, 0x40(%r13)
    vmovdqu %ymm11, (%rax,%r9,8)
    vmovdqu %ymm1, 16(%r15,%rcx,2)
    vmovdqu %ymm14, -4(%rdx,%r14,4)
    vmovdqu %xmm3, %xmm0
    vmovdqu %xmm15, %xmm2
    vmovdqu %xmm1, %xmm14
    vmovdqu %xmm12, %xmm8
    vmovdqu (%rax), %xmm14
    vmovdqu 8(%rsp), %xmm3
    vmovdqu -200(%rbp), %xmm8
    vmovdqu (%r12), %xmm7
    vmovdqu 0x40(%r13), %xmm11
    vmovdqu (%rax,%r9,8), %xmm1
    vmovdqu 16(%r15,%rcx,2), %xmm14
    vmovdqu -4(%rdx,%r14,4), %xmm3
    vmovdqu %ymm3, %ymm0
    vmovdqu %ymm15, %ymm2
    vmovdqu %ymm1, %ymm14
    vmovdqu %ymm12, %ymm8
    vmovdqu (%rax), %ymm14
    vmovdqu 8(%rsp), %ymm3
    vmovdqu -200(%rbp), %ymm8
    vmovdqu (%r12), %ymm7
    vmovdqu 0x40(%r13), %ymm11
    vmovdqu (%rax,%r9,8), %ymm1
    vmovdqu 16(%r15,%rcx,2), %ymm14
    vmovdqu -4(%rdx,%r14,4), %ymm3
    vmovdqu %xmm3, %xmm0
    vmovdqu %xmm15, %xmm2
    vmovdqu %xmm1, %xmm14
    vmovdqu %xmm12, %xmm8
    vmovdqu %xmm1, (%rax)
    vmovdqu %xmm14, 8(%rsp)
    vmovdqu %xmm3, -200(%rbp)
    vmovdqu %xmm8, (%r12)
    vmovdqu %xmm7, 0x40(%r13)
    vmovdqu %xmm11, (%rax,%r9,8)
    vmovdqu %xmm1, 16(%r15,%rcx,2)
    vmovdqu %xmm14, -4(%rdx,%r14,4)
    vmovdqu %ymm3, %ymm0
    vmovdqu %ymm15, %ymm2
    vmovdqu %ymm1, %ymm14
    vmovdqu %ymm12, %ymm8
    vmovdqu %ymm1, (%rax)
    vmovdqu %ymm14, 8(%rsp)
    vmovdqu %ymm3, -200(%rbp)
    vmovdqu %ymm8, (%r12)
    vmovdqu %ymm7, 0x40(%r13)
    vmovdqu %ymm11, (%rax,%r9,8)
    vmovdqu %ymm1, 16(%r15,%rcx,2)
    vmovdqu %ymm14, -4(%rdx,%r14,4)
    vmovdqa %ymm3, %ymm0
    vmovdqa %ymm15, %ymm2
    vmovdqa %ymm1, %ymm14
    vmovdqa %ymm12, %ymm8
    vmovdqa (%rax), %ymm14
    vmovdqa 8(%rsp), %ymm3
    vmovdqa -200(%rbp), %ymm8
    vmovdqa (%r12), %ymm7
    vmovdqa 0x40(%r13), %ymm11
    vmovdqa (%rax,%r9,8), %ymm1
    vmovdqa 16(%r15,%rcx,2), %ymm14
    vmovdqa -4(%rdx,%r14,4), %ymm3
    vmovdqa %ymm3, %ymm0
    vmovdqa %ymm15, %ymm2
    vmovdqa %ymm1, %ymm14
    vmovdqa %ymm12, %ymm8
    vmovdqa %ymm1, (%rax)
    vmovdqa %ymm14, 8(%rsp)
    vmovdqa %ymm3, -200(%rbp)
    vmovdqa %ymm8, (%r12)
    vmovdqa %ymm7, 0x40(%r13)
    vmovdqa %ymm11, (%rax,%r9,8)
    vmovdqa %ymm1, 16(%r15,%rcx,2)
    vmovdqa %ymm14, -4(%rdx,%r14,4)
    vmovdqa %xmm3, %xmm0
    vmovdqa %xmm15, %xmm2
    vmovdqa %xmm1, %xmm14
    vmovdqa %xmm12, %xmm8
    vmovdqa (%rax), %xmm14
    vmovdqa 8(%rsp), %xmm3
    vmovdqa -200(%rbp), %xmm8
    vmovdqa (%r12), %xmm7
    vmovdqa 0x40(%r13), %xmm11
    vmovdqa (%rax,%r9,8), %xmm1
    vmovdqa 16(%r15,%rcx,2), %xmm14
    vmovdqa -4(%rdx,%r14,4), %xmm3
    vmovdqa %ymm3, %ymm0
    vmovdqa %ymm15, %ymm2
    vmovdqa %ymm1, %ymm14
    vmovdqa %ymm12, %ymm8
    vmovdqa (%rax), %ymm14
    vmovdqa 8(%rsp), %ymm3
    vmovdqa -200(%rbp), %ymm8
    vmovdqa (%r12), %ymm7
    vmovdqa 0x40(%r13), %ymm11
    vmovdqa (%rax,%r9,8), %ymm1
    vmovdqa 16(%r15,%rcx,2), %ymm14
    vmovdqa -4(%rdx,%r14,4), %ymm3
    vmovdqa %xmm3, %xmm0
    vmovdqa %xmm15, %xmm2
    vmovdqa %xmm1, %xmm14
    vmovdqa %xmm12, %xmm8
    vmovdqa %xmm1, (%rax)
    vmovdqa %xmm14, 8(%rsp)
    vmovdqa %xmm3, -200(%rbp)
    vmovdqa %xmm8, (%r12)
    vmovdqa %xmm7, 0x40(%r13)
    vmovdqa %xmm11, (%rax,%r9,8)
    vmovdqa %xmm1, 16(%r15,%rcx,2)
    vmovdqa %xmm14, -4(%rdx,%r14,4)
    vmovdqa %ymm3, %ymm0
    vmovdqa %ymm15, %ymm2
    vmovdqa %ymm1, %ymm14
    vmovdqa %ymm12, %ymm8
    vmovdqa %ymm1, (%rax)
    vmovdqa %ymm14, 8(%rsp)
    vmovdqa %ymm3, -200(%rbp)
    vmovdqa %ymm8, (%r12)
    vmovdqa %ymm7, 0x40(%r13)
    vmovdqa %ymm11, (%rax,%r9,8)
    vmovdqa %ymm1, 16(%r15,%rcx,2)
    vmovdqa %ymm14, -4(%rdx,%r14,4)
    pslld $0x7f, %xmm3
    pslld $0xff, %xmm15
    pslld %xmm7, %xmm2
    pslld %xmm9, %xmm6
    pslld %xmm3, %xmm8
    pslld %xmm15, %xmm11
    pslld (%rax), %xmm14
    pslld 8(%rsp), %xmm3
    pslld -200(%rbp), %xmm8
    pslld (%r12), %xmm7
    pslld 0x40(%r13), %xmm11
    pslld (%rax,%r9,8), %xmm1
    pslld 16(%r15,%rcx,2), %xmm14
    pslld -4(%rdx,%r14,4), %xmm3
    psllq $0xff, %xmm7
    psllq $0, %xmm9
    psllq %xmm1, %xmm6
    psllq %xmm12, %xmm0
    psllq %xmm7, %xmm11
    psllq %xmm9, %xmm14
    psllq (%rax), %xmm14
    psllq 8(%rsp), %xmm3
    psllq -200(%rbp), %xmm8
    psllq (%r12), %xmm7
    psllq 0x40(%r13), %xmm11
    psllq (%rax,%r9,8), %xmm1
    psllq 16(%r15,%rcx,2), %xmm14
    psllq -4(%rdx,%r14,4), %xmm3
    vzeroupper
