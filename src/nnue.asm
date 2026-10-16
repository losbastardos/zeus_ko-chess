; ============================================================
; Copyright (c) 2026 Marek Suchy <marek.suchy@gmail.com>
; Vsetky prava vyhradene / All rights reserved.
; ============================================================

; ============================================================
; nnue.asm - NNUE loader (faza 1: linearny PST model)
;
; Format net.nnue (little-endian):
;   magic "NNUE" u32, version u32 (=1)
;   MG: own[6][64] int16, enemy[6][64] int16
;   EG: own[6][64] int16, enemy[6][64] int16
;   spolu 3080 bajtov
;
; own/enemy su rel. strane na tahu (STM); figurky opacnej farby ako
; STM sa mirroruju (rel_sq = sq ^ 56). Loader nakopiruje hodnoty do
; pst_runtime_mg/eg layoutu [own 7x64][enemy 7x64] per faza
; (slot 0 = empty zostava nulovy), int16 -> int8 clip.
; Pri chybe suboru/magicu/verzie vrati eax=1 (caller fallback classic).
; ============================================================

%include "chess.inc"

DEFAULT REL

%define NNUE_MAGIC    0x45554e4e   ; "NNUE" little-endian
%define NNUE_VERSION  1
%define NNUE_FILESIZE (8 + 4*6*64*2)


section .bss
nnue_buf: resb NNUE_FILESIZE

section .text
global nnue_load
extern pst_runtime_mg, pst_runtime_eg

; ============================================================
; nnue_load - nacita net subor do pst_runtime tabuliek
; Vstup:  rdi = cesta (NUL-terminated)
; Vystup: eax = 0 OK, 1 = chyba
; ============================================================
nnue_load:
    push rbx
    push r12
    push r13
    push r14
    ; open(path, O_RDONLY) - rdi uz obsahuje cestu
    mov rax, SYS_OPEN
    xor esi, esi                 ; O_RDONLY
    xor edx, edx
    syscall
    test rax, rax
    js .fail
    mov r12, rax                 ; fd
    ; read cely subor
    mov rax, SYS_READ
    mov rdi, r12
    lea rsi, [nnue_buf]
    mov rdx, NNUE_FILESIZE
    syscall
    mov r13, rax                 ; nacitane bajty
    mov rax, SYS_CLOSE
    mov rdi, r12
    syscall
    cmp r13, NNUE_FILESIZE
    jl .fail
    ; magic + verzia
    mov eax, dword [nnue_buf]
    cmp eax, NNUE_MAGIC
    jne .fail
    mov eax, dword [nnue_buf + 4]
    cmp eax, NNUE_VERSION
    jne .fail
    ; 4 sekcie: MG own, MG enemy, EG own, EG enemy
    ; zdroj offset v bufri: 8 + sekcia*768 ; kazda sekcia = 6 fig x 128 B
    ; ciel: faza baza + (sekcia&1 ? 7*64 : 0) + (fig+1)*64
    xor r14, r14                 ; sekcia 0..3
.sect_loop:
    cmp r14, 4
    jae .ok
    ; zdrojovy base = nnue_buf + 8 + sekcia*768
    mov rax, r14
    imul rax, rax, 768
    lea rbx, [nnue_buf + 8]
    add rbx, rax                 ; rbx = zdroj
    ; cielovy base: sekcia 0,1 -> mg ; 2,3 -> eg ; own (0,2) / enemy (1,3)
    mov rax, r14
    shr rax, 1                   ; 0 = mg, 1 = eg
    lea rdx, [pst_runtime_mg]
    cmp rax, 0
    je .phase_ok
    lea rdx, [pst_runtime_eg]
.phase_ok:
    mov rax, r14
    and rax, 1
    imul rax, rax, 7*64          ; enemy = +7*64 bajtov
    lea r13, [rdx + rax]         ; ciel base
    ; 6 figurok
    xor r12, r12                 ; fig 0..5
.fig_loop:
    cmp r12, 6
    jae .next_sect
    ; zdroj: rbx + fig*128 ; ciel: r13 + (fig+1)*64
    mov rax, r12
    shl rax, 7                   ; fig*128 (int16 = 2B)
    lea rsi, [rbx + rax]
    mov rax, r12
    shl rax, 6                   ; fig*64
    lea rdi, [r13 + rax]
    add rdi, 64                  ; +64 = preskoc empty slot 0
    ; skopiruj 64 hodnot s int8 clip
    xor rcx, rcx
.copy_loop:
    cmp rcx, 64
    jae .next_fig
    movsx eax, word [rsi + rcx*2]
    cmp eax, 127
    jle .clip_lo
    mov eax, 127
.clip_lo:
    cmp eax, -128
    jge .clip_done
    mov eax, -128
.clip_done:
    mov [rdi + rcx], al
    inc rcx
    jmp .copy_loop
.next_fig:
    inc r12
    jmp .fig_loop
.next_sect:
    inc r14
    jmp .sect_loop
.ok:
    xor eax, eax
    jmp .ret
.fail:
    mov eax, 1
.ret:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ============================================================
; NNUE faza 2: 1-skryta-vrstva forward pass
; Format net v2: magic, ver=2, H, shift1, shift2, b1q[H] i32,
; W1q[F x H] i16 (feature-major: W1[i*H + j]), b2q i32, W2q[H] i16
; Inference: acc[j] = sum_i x[i]*W1q[i*H+j] + b1q[j]
;            h[j]   = clip(acc[j] >> shift1, 0, 255)
;            eval   = (sum_j h[j]*W2q[j] + b2q) >> shift2   (cp)
; Feature indexy (zhodne s trainerom):
;   non-king: (own*5 + typ-1)*64 + rel_sq ; king: 640 + own*64 + rel_sq
;   own = (farba figury == strana na tahu) ? 0 : 1
;   rel_sq = (strana na tahu == biela) ? sq : sq ^ 56
; ============================================================

%define NNUE2_F 768
%define NNUE2_MAXH 256

section .bss
nnue2_buf:   resb 150000
nnue2_ready: resb 1
; Perzistentny akumulator (E10/F2): acc[perspektiva 0/1][j] int32,
; perspektiva = strana, z ktorej pohladu su featury (0 = biela, 1 = cierna).
; nnue_acc_hash = position_hash pozicie, pre ktoru je acc platny
; (pokial sa nezhoduje, eval robi refresh; sluzi aj ako invalidacia
; pri FEN/init/UI tahoch, ktore menia board mimo make/unmake).
nnue_accum:     resd 2*NNUE2_MAXH
nnue_acc_valid: resb 1
nnue_acc_hash:  resq 1

global nnue2_ready, nnue_acc_valid, nnue_acc_hash

section .data
nnue2_H:      dd 0
nnue2_shift1: dd 0
nnue2_shift2: dd 0

section .text
global nnue2_load, nnue2_eval
global nnue2_feature_idx, nnue2_refresh
global nnue2_halfkp_idx, nnue2_halfkp_collect
global nnue2_move_delta, nnue2_move_delta_inv
global nnue2_fwd
extern board, side, position_hash, moved_piece, captured_piece, promo_pieces

; ============================================================
; nnue2_load - nacita net v2 do buffra
; Vstup: rdi = cesta ; Vystup: eax = 0 OK, 1 chyba
; ============================================================
nnue2_load:
    push rbx
    push r12
    mov rax, SYS_OPEN
    xor esi, esi
    xor edx, edx
    syscall
    test rax, rax
    js .fail
    mov r12, rax
    mov rax, SYS_READ
    mov rdi, r12
    lea rsi, [nnue2_buf]
    mov rdx, 150000
    syscall
    mov rbx, rax                 ; nacitane
    mov rax, SYS_CLOSE
    mov rdi, r12
    syscall
    cmp rbx, 148000              ; minimalna velkost (H=96)
    jl .fail
    cmp dword [nnue2_buf], NNUE_MAGIC
    jne .fail
    cmp dword [nnue2_buf + 4], 2
    jne .fail
    mov eax, dword [nnue2_buf + 8]
    mov [nnue2_H], eax
    mov eax, dword [nnue2_buf + 12]
    mov [nnue2_shift1], eax
    mov eax, dword [nnue2_buf + 16]
    mov [nnue2_shift2], eax
    mov byte [nnue2_ready], 1
    xor eax, eax
    pop r12
    pop rbx
    ret
.fail:
    mov eax, 1
    pop r12
    pop rbx
    ret

; ============================================================
; nnue2_feature_idx - feature index jednej figurky
; Vstup:  eax = sq (0..63), ecx = piece bajt (typ|farba), edx = strana
;         perspektivy (0 biela / 1 cierna)
; Vystup: eax = idx 0..767
;   non-king: (own*5 + typ-1)*64 + rel_sq ; king: 640 + own*64 + rel_sq
;   own = (farba figury == perspektiva) ? 0 : 1
;   rel_sq = sq ^ 56 ak je perspektiva cierna
; Clobbers: rax, rcx, rdx, rsi (iba caller-saved)
; ============================================================
nnue2_feature_idx:
    mov esi, eax                 ; rel_sq = sq
    test edx, edx
    jz .fidx_rsq_ok
    xor esi, 56
.fidx_rsq_ok:
    mov eax, ecx
    and eax, COLOR_MASK
    shr eax, 3                   ; farba figury 0/1
    xor eax, edx                 ; own
    and ecx, PIECE_MASK          ; typ 1..6
    cmp ecx, KING
    je .fidx_king
    dec ecx                      ; typ-1 0..4
    imul eax, eax, 5
    add eax, ecx                 ; own*5 + typ-1
    shl eax, 6                   ; *64
    add eax, esi
    ret

.fidx_king:
    shl eax, 6                   ; own*64
    add eax, 640
    add eax, esi
    ret

; ============================================================
; nnue2_halfkp_idx - HalfKP index non-king figurky
; Vstup:  eax = sq (0..63), ecx = piece bajt (typ|farba),
;         edx = perspektiva farby (0 biela / 1 cierna), r8d = king_rel (0..63)
; Vystup: eax = idx 0..40959
; Formula: (((own*64 + king_rel)*5 + (typ-1))*64 + rel_sq)
;   own = (farba figury == perspektiva) ? 0 : 1
;   rel_sq = sq ^ 56 ak je perspektiva cierna
; Poznamka: caller zabezpeci non-king typ (P..Q).
; ============================================================
nnue2_halfkp_idx:
    mov esi, eax                 ; rel_sq = sq
    test edx, edx
    jz .hk_rsq_ok
    xor esi, 56
.hk_rsq_ok:
    mov eax, ecx
    and eax, COLOR_MASK
    shr eax, 3                   ; farba figury 0/1
    xor eax, edx                 ; own
    and ecx, PIECE_MASK          ; typ 1..6
    dec ecx                      ; typ-1 0..4 (caller filtruje K)
    shl eax, 6                   ; own*64
    add eax, r8d                 ; own*64 + king_rel
    imul eax, eax, 5
    add eax, ecx                 ; (...)*5 + typ-1
    shl eax, 6                   ; *64
    add eax, esi                 ; + rel_sq
    ret

; ============================================================
; nnue2_halfkp_collect - zozbiera a zoradi HalfKP idx pre perspektivu
; Vstup:  edx = perspektiva farby (0 biela / 1 cierna)
;         rdi = cielovy buffer (dword idx[64])
; Vystup: eax = count, ecx = king_rel (0..63), alebo 255 ak king nenajdeny
; Poznamka: pouziva ten isty indexovac ako inference/debug dump.
; ============================================================
nnue2_halfkp_collect:
    push rbx
    push r12
    push r13
    push r14
    mov r12d, edx                ; perspektiva farby
    mov r13, rdi                 ; idx buffer
    lea rbx, [board]

    ; najdi krala danej perspektivy
    mov ecx, 255                 ; king_rel default = invalid
    xor r10d, r10d               ; sq
.find_king:
    cmp r10d, 64
    jae .king_done
    movzx eax, byte [rbx + r10]
    test eax, eax
    jz .find_king_next
    mov edx, eax
    and edx, PIECE_MASK
    cmp edx, KING
    jne .find_king_next
    mov edx, eax
    and edx, COLOR_MASK
    shr edx, 3
    cmp edx, r12d
    jne .find_king_next
    mov ecx, r10d                ; absolutne sq krala danej perspektivy
    jmp .king_done
.find_king_next:
    inc r10d
    jmp .find_king

.king_done:
    cmp ecx, 255
    jne .have_king
    xor eax, eax
    jmp .ret

.have_king:
    test r12d, r12d
    jz .king_rel_ok
    xor ecx, 56
.king_rel_ok:
    mov r9d, ecx                 ; king_rel

    ; scan non-king figur a vypocet idx
    xor r14d, r14d               ; count
    xor r10d, r10d               ; sq
.scan_loop:
    cmp r10d, 64
    jae .sort
    movzx esi, byte [rbx + r10]
    test esi, esi
    jz .scan_next
    mov edx, esi
    and edx, PIECE_MASK
    cmp edx, PAWN
    jb .scan_next
    cmp edx, QUEEN
    ja .scan_next                ; preskoc KING
    mov eax, r10d
    mov ecx, esi
    mov edx, r12d
    mov r8d, r9d
    call nnue2_halfkp_idx
    mov [r13 + r14*4], eax
    inc r14d
.scan_next:
    inc r10d
    jmp .scan_loop

    ; insertion sort (n <= 30)
.sort:
    mov r8d, 1
.outer:
    cmp r8d, r14d
    jae .done
    mov r10d, r8d
.inner:
    test r10d, r10d
    jz .outer_next
    mov eax, [r13 + r10*4 - 4]
    mov edx, [r13 + r10*4]
    cmp eax, edx
    jle .outer_next
    mov [r13 + r10*4 - 4], edx
    mov [r13 + r10*4], eax
    dec r10d
    jmp .inner
.outer_next:
    inc r8d
    jmp .outer

.done:
    mov eax, r14d
    mov ecx, r9d
.ret:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
; ============================================================
; nnue2_acc_delta - delta akumulatora pre jednu perspektivu
; Vstup:  eax = added idx (-1 = ziaden), ecx = removed idx (-1 = ziaden),
;         edx = perspektiva (0/1)
;   acc[edx][j] += W1[added*H+j] - W1[removed*H+j], j = 0..H-1
; Clobbers: rax, rcx, rdx, rsi, rdi, r8-r11 (rbx zachovane)
; ============================================================
nnue2_acc_delta:
    push rbx
    mov r8d, [nnue2_H]           ; H
    mov r9d, edx
    shl r9d, 10                  ; persp * (MAXH*4)
    lea rdi, [nnue_accum]
    add rdi, r9                  ; acc riadok perspektivy
    mov r10d, r8d
    shl r10d, 2
    lea r11, [nnue2_buf + 20]
    add r11, r10                 ; W1 base
    ; vyber variantu este pred imul (eax/ecx sa prepisu)
    test eax, eax
    js .chk_rem
    test ecx, ecx
    js .only_add
    ; obidva: priprav oba riadky
    imul eax, r8d
    lea rsi, [r11 + rax*2]       ; W1 riadok added
    imul ecx, r8d
    lea r10, [r11 + rcx*2]       ; W1 riadok removed
    xor edx, edx
.loop_both:
    cmp edx, r8d
    jae .done
    movsx eax, word [rsi + rdx*2]
    movsx ebx, word [r10 + rdx*2]
    sub eax, ebx
    add [rdi + rdx*4], eax
    inc edx
    jmp .loop_both
.chk_rem:
    test ecx, ecx
    jns .only_rem
    jmp .done                    ; oba -1: nic
.only_add:
    imul eax, r8d
    lea rsi, [r11 + rax*2]
    xor edx, edx
.loop_add:
    cmp edx, r8d
    jae .done
    movsx eax, word [rsi + rdx*2]
    add [rdi + rdx*4], eax
    inc edx
    jmp .loop_add
.only_rem:
    imul ecx, r8d
    lea r10, [r11 + rcx*2]
    xor edx, edx
.loop_rem:
    cmp edx, r8d
    jae .done
    movsx eax, word [r10 + rdx*2]
    sub [rdi + rdx*4], eax
    inc edx
    jmp .loop_rem
.done:
    pop rbx
    ret

; ============================================================
; nnue2_delta_both - delta pary figuriek pre OBE perspektivy
; Vstup:  esi = from sq, edi = to sq, ecx = removed piece, r8d = added piece
;   acc[p] += W1[idx(to,added,p)] - W1[idx(from,removed,p)] pre p=0,1
; Clobbers: caller-saved + rbx (pushuje si)
; ============================================================
nnue2_delta_both:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8                   ; [rsp] = docasny idx
    mov r12d, esi                ; from
    mov r13d, edi                ; to
    mov r14d, ecx                ; removed piece
    mov ebx, r8d                 ; added piece
    ; --- perspektiva 0 ---
    mov eax, r13d
    mov ecx, ebx
    xor edx, edx
    call nnue2_feature_idx
    mov [rsp], rax               ; added idx
    mov eax, r12d
    mov ecx, r14d
    xor edx, edx
    call nnue2_feature_idx       ; eax = removed idx
    mov ecx, eax
    mov eax, [rsp]
    xor edx, edx
    call nnue2_acc_delta
    ; --- perspektiva 1 ---
    mov eax, r13d
    mov ecx, ebx
    mov edx, 1
    call nnue2_feature_idx
    mov [rsp], rax
    mov eax, r12d
    mov ecx, r14d
    mov edx, 1
    call nnue2_feature_idx
    mov ecx, eax
    mov eax, [rsp]
    mov edx, 1
    call nnue2_acc_delta
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ============================================================
; nnue2_remove_both - odstranenie figurky z acc (OBE perspektivy)
; Vstup: esi = sq, ecx = piece
; ============================================================
nnue2_remove_both:
    push rbx
    push r12
    sub rsp, 8                   ; zarovnanie
    mov r12d, esi
    mov ebx, ecx
    mov eax, r12d
    mov ecx, ebx
    xor edx, edx
    call nnue2_feature_idx
    mov ecx, eax
    mov eax, -1
    xor edx, edx
    call nnue2_acc_delta
    mov eax, r12d
    mov ecx, ebx
    mov edx, 1
    call nnue2_feature_idx
    mov ecx, eax
    mov eax, -1
    mov edx, 1
    call nnue2_acc_delta
    add rsp, 8
    pop r12
    pop rbx
    ret

; ============================================================
; nnue2_add_both - pridanie figurky do acc (OBE perspektivy)
; Vstup: esi = sq, ecx = piece
; ============================================================
nnue2_add_both:
    push rbx
    push r12
    sub rsp, 8                   ; zarovnanie
    mov r12d, esi
    mov ebx, ecx
    mov eax, r12d
    mov ecx, ebx
    xor edx, edx
    call nnue2_feature_idx
    mov ecx, -1
    xor edx, edx
    call nnue2_acc_delta
    mov eax, r12d
    mov ecx, ebx
    mov edx, 1
    call nnue2_feature_idx
    mov ecx, -1
    mov edx, 1
    call nnue2_acc_delta
    add rsp, 8
    pop r12
    pop rbx
    ret

; ============================================================
; nnue2_refresh - plny recompute akumulatora z board[64] pre obe
; perspektivy; acc_hash = position_hash, valid = 1
; ============================================================
nnue2_refresh:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r15d, [nnue2_H]
    ; W1 base = buf + 20 + H*4
    mov eax, r15d
    shl eax, 2
    lea r14, [nnue2_buf + 20]
    add r14, rax                 ; r14 = W1q base
    xor ebx, ebx                 ; perspektiva 0/1
.persp_loop:
    cmp ebx, 2
    jae .fin
    ; acc riadok = nnue_accum + persp*MAXH*4
    mov eax, ebx
    shl eax, 10
    lea rdi, [nnue_accum]
    add rdi, rax
    ; acc = b1q
    mov rcx, r15
    lea rsi, [nnue2_buf + 20]
.copy_b1:
    mov eax, dword [rsi]
    mov dword [rdi], eax
    add rsi, 4
    add rdi, 4
    dec rcx
    jnz .copy_b1
    ; scan board
    lea r13, [board]
    xor r12, r12                 ; sq
.sq_loop:
    cmp r12, 64
    jae .persp_next
    movzx ecx, byte [r13 + r12]
    test ecx, ecx
    jz .sq_next
    mov eax, r12d
    mov edx, ebx                 ; perspektiva
    call nnue2_feature_idx       ; eax = idx
    imul eax, r15d               ; idx*H
    lea rsi, [r14 + rax*2]       ; W1 riadok
    mov r9d, ebx
    shl r9d, 10
    lea r8, [nnue_accum]
    add r8, r9                   ; acc riadok perspektivy
    xor edx, edx
.acc_loop:
    cmp edx, r15d
    jae .sq_next
    movsx ecx, word [rsi + rdx*2]
    add [r8 + rdx*4], ecx
    inc edx
    jmp .acc_loop
.sq_next:
    inc r12
    jmp .sq_loop
.persp_next:
    inc ebx
    jmp .persp_loop
.fin:
    mov byte [nnue_acc_valid], 1
    mov rax, [position_hash]
    mov [nnue_acc_hash], rax
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ============================================================
; nnue2_eval - forward pass z akumulatora
; Vstup:  nnue_acc_valid + zhoda nnue_acc_hash s position_hash urcuju
;         platnost acc; inak sa spravi refresh
; Vystup: eax = eval cp (STM perspektiva) — identicky vystup ako doteraz
; ============================================================
nnue2_eval:
    cmp byte [nnue_acc_valid], 1
    jne .refresh
    mov rax, [nnue_acc_hash]
    cmp rax, [position_hash]
    je .have_acc
.refresh:
    call nnue2_refresh
.have_acc:
    jmp nnue2_fwd

; ============================================================
; nnue2_fwd - forward pass (CReLU -> W2 -> b2 -> shift2) z acc
; Vystup: eax = eval cp (STM perspektiva)
; ============================================================
nnue2_fwd:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r15d, [nnue2_H]
    ; acc riadok strany na tahu
    movzx eax, byte [side]
    shl eax, 10
    lea r13, [nnue_accum]
    add r13, rax                 ; r13 = acc[side]
    ; W1 base = buf + 20 + H*4
    mov eax, r15d
    shl eax, 2
    lea r14, [nnue2_buf + 20]
    add r14, rax
    ; W2 base = W1 + F*H*2 + 4 (za W1 nasleduje b2q i32, az potom W2q)
    mov eax, NNUE2_F
    imul eax, r15d               ; F*H
    lea rsi, [r14 + rax*2 + 4]   ; W2q
    mov ebx, eax
    shl ebx, 1
    lea rdi, [r14 + rbx]         ; b2q (int32)
    mov ebx, dword [rdi]         ; sum = b2q
    mov ecx, [nnue2_shift1]
    xor r12, r12                 ; j
.out_loop:
    cmp r12, r15
    jae .finish
    mov eax, dword [r13 + r12*4]
    sar eax, cl                  ; acc >> shift1
    cmp eax, 0
    jge .clip_hi
    xor eax, eax
.clip_hi:
    cmp eax, 255
    jle .clip_ok
    mov eax, 255
.clip_ok:
    movsx edx, word [rsi + r12*2]
    imul eax, edx
    add ebx, eax
    inc r12
    jmp .out_loop
.finish:
    mov ecx, [nnue2_shift2]
    sar ebx, cl
    mov eax, ebx
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ============================================================
; nnue2_move_delta / nnue2_move_delta_inv - inkrementalny update
; akumulatora po tahu (make smer / inverzne pre unmake)
; Vstup:  ax = 16-bitovy tah, rdi = undo zaznam base
;   moved_piece / captured_piece musia byt nastavene:
;     make:  po apply_move
;     unmake: po nacitani z undo zaznamu (este pred board restore)
; Vystup: eax = 1 ak sa delta aplikovala, inak 0 (acc neplatny — search
;   nesmie synchronizovat acc_hash).
; Delta sa aplikuje len ak je acc platny pre aktualnu poziciu
; (nnue2_ready, valid, acc_hash == position_hash); inak sa acc necha
; stary — eval spravi refresh.
; Do undo zaznamu (+11..15) zapise removed/added idx (white-POV) + flags:
;   +11..12 removed_idx (word), +13..14 added_idx (word),
;   +15 flag bity (bit0 promo, bit1 capture, bit2 ep, bit3 castle)
; ============================================================
nnue2_move_delta:
    cmp byte [nnue2_ready], 1
    jne .skip
    cmp byte [nnue_acc_valid], 1
    jne .skip
    xor edx, edx                 ; smer 0 = make
    jmp nnue2_move_delta_core
.skip:
    xor eax, eax
    ret

nnue2_move_delta_inv:
    cmp byte [nnue2_ready], 1
    jne .skip
    cmp byte [nnue_acc_valid], 1
    jne .skip
    mov edx, 1                   ; smer 1 = unmake
    jmp nnue2_move_delta_core
.skip:
    xor eax, eax
    ret

; jadro: [rsp+8] = tah, [rsp+16] = smer, [rsp+24] = undo base
nnue2_move_delta_core:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rdi
    push rdx
    push rax
    sub rsp, 8                   ; zarovnanie (8 pushov + ret = misaligned)
    ; platnost acc voci aktualnej pozicii (hash este nebol zmeneny)
    mov rax, [nnue_acc_hash]
    cmp rax, [position_hash]
    jne .skip
    movzx eax, word [rsp + 8]    ; tah
    movzx r12d, ax
    and r12d, 0x3F               ; from
    mov r13d, eax
    shr r13d, 6
    and r13d, 0x3F               ; to
    mov r14d, eax
    shr r14d, 12                 ; flags
    ; undo +15: flag bity (bit0 promo, bit1 capture, bit2 ep, bit3 castle)
    xor ecx, ecx
    cmp r14d, FLAG_PROMO_Q
    jb .f1
    cmp r14d, FLAG_PROMO_N
    ja .f1
    or ecx, 1
.f1:
    movzx r15d, byte [captured_piece]
    test r15d, r15d
    jz .f2
    or ecx, 2
    cmp r14d, FLAG_ENPASSANT
    jne .f2
    or ecx, 4
.f2:
    cmp r14d, FLAG_CASTLE
    jne .f3
    or ecx, 8
.f3:
    mov rax, [rsp + 24]
    mov [rax + 15], cl
    ; removed = moved_piece (at from); added = promo ? nova figurka : moved (at to)
    movzx r15d, byte [moved_piece]
    mov ebx, r15d
    cmp r14d, FLAG_PROMO_Q
    jb .np
    cmp r14d, FLAG_PROMO_N
    ja .np
    lea rcx, [promo_pieces]
    movzx ebx, byte [rcx + r14]
    movzx ecx, byte [moved_piece]
    and ecx, COLOR_MASK
    or ebx, ecx
.np:
    ; undo +11..14: white-POV (perspektiva 0) idx
    mov eax, r12d
    mov ecx, r15d
    xor edx, edx
    call nnue2_feature_idx
    mov rcx, [rsp + 24]
    mov [rcx + 11], ax           ; removed idx
    mov eax, r13d
    mov ecx, ebx
    xor edx, edx
    call nnue2_feature_idx
    mov rcx, [rsp + 24]
    mov [rcx + 13], ax           ; added idx
    ; par hybanej figurky: make from->to, unmake to->from
    cmp qword [rsp + 16], 0
    jne .inv_pair
    mov esi, r12d
    mov edi, r13d
    mov ecx, r15d
    mov r8d, ebx
    call nnue2_delta_both
    jmp .cap
.inv_pair:
    mov esi, r13d
    mov edi, r12d
    mov ecx, ebx
    mov r8d, r15d
    call nnue2_delta_both
.cap:
    ; brana figurka (cap sq = to, pri EP to-+8 podla farby hybacej)
    movzx ecx, byte [captured_piece]
    test ecx, ecx
    jz .castle
    mov esi, r13d
    cmp r14d, FLAG_ENPASSANT
    jne .cap_go
    movzx eax, byte [moved_piece]
    test eax, COLOR_MASK
    jnz .ep_b
    sub esi, 8
    jmp .cap_go
.ep_b:
    add esi, 8
.cap_go:
    cmp qword [rsp + 16], 0
    jne .cap_inv
    call nnue2_remove_both
    jmp .castle
.cap_inv:
    call nnue2_add_both
.castle:
    cmp r14d, FLAG_CASTLE
    jne .done
    cmp r13d, 6
    je .rwk
    cmp r13d, 2
    je .rwq
    cmp r13d, 62
    je .rbk
    cmp r13d, 58
    je .rbq
    jmp .done
.rwk:
    mov esi, 7
    mov edi, 5
    jmp .rook
.rwq:
    mov esi, 0
    mov edi, 3
    jmp .rook
.rbk:
    mov esi, 63
    mov edi, 61
    jmp .rook
.rbq:
    mov esi, 56
    mov edi, 59
.rook:
    movzx ecx, byte [moved_piece]
    and ecx, COLOR_MASK
    or ecx, ROOK                 ; veza = removed aj added
    cmp qword [rsp + 16], 0
    jne .rook_inv
    mov r8d, ecx
    call nnue2_delta_both
    jmp .done
.rook_inv:
    mov r8d, ecx
    xchg esi, edi                ; inverzne poradie from/to
    call nnue2_delta_both
.done:
    mov eax, 1                   ; delta aplikovana
    jmp .out
.skip:
    xor eax, eax                 ; delta preskocena (acc neplatny)
.out:
    add rsp, 8                   ; pad
    add rsp, 8                   ; rax (vysledok sa neobnovuje)
    pop rdx
    pop rdi
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
