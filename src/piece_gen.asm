; ============================================================
; Copyright (c) 2026 Marek Suchy <marek.suchy@gmail.com>
; Vsetky prava vyhradene / All rights reserved.
; ============================================================

; ============================================================
; piece_gen.asm - proceduralne generovanie bitmap figuriek
; 16x16 px, 1 bit/px, 2 bajty/riadok, bit7 = lavy pixel
; Maska je farbovo neutralna: renderer farbi podla piece byte.
; Generuje sa 6 unikatnych masiek (P N B R Q K) do 192 B .bss.
; ============================================================

%include "chess.inc"

DEFAULT REL

; ============================================================
; GEN_PX - interne makro: set/clear jedneho pixelu v maske
; Vstup: %1 = x (reg, cita sa ako prvy), %2 = y (reg, cita sa ako prvy)
;        %3 = bts | btr
; Clipuje na gen_clip (7 alebo 15), riadkova stride = gen_stride (1/2 bajty).
; Clobber: rax, rcx, rdx, r10, r11
; ============================================================
%macro GEN_PX 3
    cmp %1, [gen_clip]
    ja %%skip
    cmp %2, [gen_clip]
    ja %%skip
    mov r11, [gen_cur]
    mov eax, %2
    cmp dword [gen_stride], 2
    jne %%s1
    add eax, eax                    ; 2 bajty/riadok
%%s1:
    mov ecx, %1
    cmp ecx, 8
    jb %%lo
    inc eax                         ; druhy bajt (x 8-15)
    sub ecx, 8
%%lo:
    and ecx, 7
    movzx edx, byte [r11 + rax]
    mov r10d, 7
    sub r10d, ecx                   ; bit 7 = lavy pixel
    %3 edx, r10d
    mov [r11 + rax], dl
%%skip:
%endmacro

; ============================================================
; DUMP_MASK - interne makro: vytlaci jednu masku ako #/.
; Vstup: %1 = meno C-stringu, %2 = index masky
; Ocakava pushnute rbx, r12, r13, r14 (robi sa v piece_gen_dump)
; ============================================================
%macro DUMP_MASK 2
    lea rdi, [%1]
    call write_cstr
    mov ebx, %2
    shl ebx, 5
    lea r12, [piece_bitmaps]
    add r12, rbx
    xor r13d, r13d                  ; y
%%row:
    xor r14d, r14d                  ; x
%%col:
    mov eax, r13d
    add eax, eax                    ; 2 bajty/riadok
    cmp r14d, 8
    jb %%lo
    inc eax
%%lo:
    movzx edx, byte [r12 + rax]
    mov ecx, r14d
    and ecx, 7
    mov r10d, 7
    sub r10d, ecx
    bt edx, r10d
    mov cl, '.'
    jnc %%store
    mov cl, '#'
%%store:
    mov [gen_dump_buf + r14], cl
    inc r14d
    cmp r14d, 16
    jl %%col
    mov byte [gen_dump_buf + 16], 10
    mov byte [gen_dump_buf + 17], 0
    lea rdi, [gen_dump_buf]
    call write_cstr
    inc r13d
    cmp r13d, 16
    jl %%row
    lea rdi, [dump_nl]
    call write_cstr
%endmacro

; ============================================================
; DUMP_MASK8 - interne makro: vytlaci jednu 8x8 masku (1 bajt/riadok)
; Vstup: %1 = meno C-stringu, %2 = index masky
; ============================================================
%macro DUMP_MASK8 2
    lea rdi, [%1]
    call write_cstr
    mov ebx, %2
    shl ebx, 3
    lea r12, [piece_bitmaps_8]
    add r12, rbx
    xor r13d, r13d                  ; y
%%row:
    xor r14d, r14d                  ; x
%%col:
    movzx edx, byte [r12 + r13]
    mov ecx, r14d
    mov r10d, 7
    sub r10d, ecx
    bt edx, r10d
    mov cl, '.'
    jnc %%store
    mov cl, '#'
%%store:
    mov [gen_dump_buf + r14], cl
    inc r14d
    cmp r14d, 8
    jl %%col
    mov byte [gen_dump_buf + 8], 10
    mov byte [gen_dump_buf + 9], 0
    lea rdi, [gen_dump_buf]
    call write_cstr
    inc r13d
    cmp r13d, 8
    jl %%row
    lea rdi, [dump_nl]
    call write_cstr
%endmacro

section .data

dump_name_p: db "Pawn:", 10, 0
dump_name_n: db "Knight:", 10, 0
dump_name_b: db "Bishop:", 10, 0
dump_name_r: db "Rook:", 10, 0
dump_name_q: db "Queen:", 10, 0
dump_name_k: db "King:", 10, 0
dump_nl:     db 10, 0
dump8_name_p: db "Pawn8:", 10, 0
dump8_name_n: db "Knight8:", 10, 0
dump8_name_b: db "Bishop8:", 10, 0
dump8_name_r: db "Rook8:", 10, 0
dump8_name_q: db "Queen8:", 10, 0
dump8_name_k: db "King8:", 10, 0

section .bss

global piece_bitmaps
piece_bitmaps:  resb 192            ; 6 masiek x 32 B (16x16, P N B R Q K)

global piece_bitmaps_8
piece_bitmaps_8: resb 48            ; 6 masiek x 8 B (8x8, P N B R Q K)

gen_cur:        resq 1              ; ukazatel na aktualnu masku
gen_clip:       resd 1              ; max suradnica (7 = 8x8, 15 = 16x16)
gen_stride:     resd 1              ; bajty na riadok (1 = 8x8, 2 = 16x16)
gen_dump_buf:   resb 32

section .text

global piece_gen_init
extern debug, write_cstr

; ============================================================
; gen_select - vyberie 16x16 masku a vynuluje ju
; Vstup: rdi = index 0..5
; ============================================================
gen_select:
    mov dword [gen_clip], 15
    mov dword [gen_stride], 2
    mov eax, edi
    shl eax, 5
    lea rcx, [piece_bitmaps]
    add rcx, rax
    mov [gen_cur], rcx
    xor eax, eax
    mov [rcx], rax
    mov [rcx+8], rax
    mov [rcx+16], rax
    mov [rcx+24], rax
    ret

; ============================================================
; gen_select8 - vyberie 8x8 masku (1 bajt/riadok) a vynuluje ju
; Vstup: rdi = index 0..5
; ============================================================
gen_select8:
    mov dword [gen_clip], 7
    mov dword [gen_stride], 1
    mov eax, edi
    shl eax, 3
    lea rcx, [piece_bitmaps_8]
    add rcx, rax
    mov [gen_cur], rcx
    mov qword [rcx], 0              ; 8 bajtov naraz
    ret

; ============================================================
; gen_fill_rect - vyplneny obdlznik
; Vstup: rdi = x, rsi = y, rdx = w, rcx = h
; ============================================================
gen_fill_rect:
    push rbx
    push r12
    mov r8d, esi                    ; y
    mov r9d, ecx                    ; h
    mov r12d, edx                   ; w
    xor esi, esi                    ; riadok
.row:
    cmp esi, r9d
    jae .done
    xor ebx, ebx                    ; stlpec
.col:
    cmp ebx, r12d
    jae .next_row
    lea ecx, [rdi + rbx]            ; px
    lea r10d, [r8 + rsi]            ; py
    GEN_PX ecx, r10d, bts
    inc ebx
    jmp .col
.next_row:
    inc esi
    jmp .row
.done:
    pop r12
    pop rbx
    ret

; ============================================================
; gen_fill_circle - vyplneny kruh (test d^2 <= r^2)
; Vstup: rdi = cx, rsi = cy, rdx = r
; ============================================================
gen_fill_circle:
    push rbx
    push rbp
    push r12
    mov r8d, edi                    ; cx
    mov r9d, esi                    ; cy
    mov r12d, edx                   ; r
    mov ebx, edx
    neg ebx                         ; dy = -r
.dy:
    cmp ebx, r12d
    jg .done
    mov ebp, r12d
    neg ebp                         ; dx = -r
.dx:
    cmp ebp, r12d
    jg .next_dy
    mov eax, ebp
    imul eax, eax
    mov ecx, ebx
    imul ecx, ecx
    add eax, ecx                    ; dx^2 + dy^2
    mov ecx, r12d
    imul ecx, ecx                   ; r^2
    cmp eax, ecx
    ja .skip
    lea ecx, [r8 + rbp]             ; px = cx + dx
    lea r10d, [r9 + rbx]            ; py = cy + dy
    GEN_PX ecx, r10d, bts
.skip:
    inc ebp
    jmp .dx
.next_dy:
    inc ebx
    jmp .dy
.done:
    pop r12
    pop rbp
    pop rbx
    ret

; ============================================================
; gen_line - Bresenham ciara
; Vstup: rdi = x0, rsi = y0, rdx = x1, rcx = y1
;        r8b = 0 -> set pixel, 1 -> clear pixel
; ============================================================
gen_line:
    push r12
    push r13
    push r14
    push r15
    sub rsp, 32
    ; [rsp]    = dx
    ; [rsp+4]  = dy (zaporne)
    ; [rsp+8]  = sx
    ; [rsp+12] = sy
    ; [rsp+16] = err
    mov r12d, edi                   ; x
    mov r13d, esi                   ; y
    mov r14d, edx                   ; x1
    mov r15d, ecx                   ; y1
    ; dx = |x1-x0|, sx = +/-1
    mov eax, r14d
    sub eax, edi
    mov ecx, 1
    test eax, eax
    jns .sx_ok
    neg eax
    neg ecx
.sx_ok:
    mov [rsp], eax
    mov [rsp+8], ecx
    ; dy = -|y1-y0|, sy = +/-1
    mov eax, r15d
    sub eax, esi
    mov ecx, 1
    test eax, eax
    jns .sy_ok
    neg eax
    neg ecx
.sy_ok:
    neg eax
    mov [rsp+4], eax
    mov [rsp+12], ecx
    mov eax, [rsp]
    add eax, [rsp+4]
    mov [rsp+16], eax               ; err = dx + dy
.loop:
    mov ecx, r12d
    mov r10d, r13d
    test r8b, r8b
    jnz .clear
    GEN_PX ecx, r10d, bts
    jmp .plotted
.clear:
    GEN_PX ecx, r10d, btr
.plotted:
    cmp r12d, r14d
    jne .cont
    cmp r13d, r15d
    je .done
.cont:
    mov eax, [rsp+16]
    add eax, eax                    ; e2 = 2*err
    mov ecx, [rsp+4]
    cmp eax, ecx
    jl .no_x
    add [rsp+16], ecx
    add r12d, [rsp+8]
.no_x:
    mov ecx, [rsp]
    cmp eax, ecx
    jg .loop
    add [rsp+16], ecx
    add r13d, [rsp+12]
    jmp .loop
.done:
    add rsp, 32
    pop r15
    pop r14
    pop r13
    pop r12
    ret

; ============================================================
; gen_fill_triangle - vyplneny trojuholnik (scanline bbox test)
; Vstup: rdi = x0, rsi = y0, rdx = x1, rcx = y1, r8d = x2, r9d = y2
; ============================================================
gen_fill_triangle:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 24
    ; [rsp]    = x2
    ; [rsp+4]  = y2
    ; [rsp+8]  = miny
    ; [rsp+12] = maxy
    ; [rsp+16] = py
    ; [rsp+20] = minx (reset px)
    mov r12d, edi                   ; x0
    mov r13d, esi                   ; y0
    mov r14d, edx                   ; x1
    mov r15d, ecx                   ; y1
    mov [rsp], r8d                  ; x2
    mov [rsp+4], r9d                ; y2
    ; minx / maxx
    mov ebx, r12d
    cmp r14d, ebx
    cmovl ebx, r14d
    mov eax, [rsp]
    cmp eax, ebx
    cmovl ebx, eax
    mov [rsp+20], ebx               ; minx
    mov ebp, r12d
    cmp r14d, ebp
    cmovg ebp, r14d
    mov eax, [rsp]
    cmp eax, ebp
    cmovg ebp, eax                  ; ebp = maxx
    ; miny / maxy
    mov eax, r13d
    cmp r15d, eax
    cmovl eax, r15d
    mov ecx, [rsp+4]
    cmp ecx, eax
    cmovl eax, ecx
    mov [rsp+8], eax                ; miny
    mov eax, r13d
    cmp r15d, eax
    cmovg eax, r15d
    mov ecx, [rsp+4]
    cmp ecx, eax
    cmovg eax, ecx
    mov [rsp+12], eax               ; maxy
    mov eax, [rsp+8]
    mov [rsp+16], eax               ; py = miny
    mov rbx, [rsp+20]               ; px = minx
.py_loop:
    mov eax, [rsp+16]
    cmp eax, [rsp+12]
    jg .done
.px_loop:
    cmp ebx, ebp
    jg .px_done
    ; d1 = (py-y0)*(x1-x0) - (px-x0)*(y1-y0)
    mov eax, [rsp+16]
    sub eax, r13d
    mov ecx, r14d
    sub ecx, r12d
    imul eax, ecx
    mov ecx, ebx
    sub ecx, r12d
    mov edx, r15d
    sub edx, r13d
    imul ecx, edx
    sub eax, ecx                    ; d1
    mov r10d, eax
    ; d2 = (py-y1)*(x2-x1) - (px-x1)*(y2-y1)
    mov eax, [rsp+16]
    sub eax, r15d
    mov ecx, [rsp]
    sub ecx, r14d
    imul eax, ecx
    mov ecx, ebx
    sub ecx, r14d
    mov edx, [rsp+4]
    sub edx, r15d
    imul ecx, edx
    sub eax, ecx                    ; d2
    mov r11d, eax
    ; d3 = (py-y2)*(x0-x2) - (px-x2)*(y0-y2)
    mov eax, [rsp+16]
    sub eax, [rsp+4]
    mov ecx, r12d
    sub ecx, [rsp]
    imul eax, ecx
    mov ecx, ebx
    sub ecx, [rsp]
    mov edx, r13d
    sub edx, [rsp+4]
    imul ecx, edx
    sub eax, ecx                    ; d3
    ; vnutri ak d1,d2,d3 nemaju zmiesane znamienka (nuly patria dovnutra)
    xor ecx, ecx                    ; any > 0
    xor edx, edx                    ; any < 0
    cmp r10d, 0
    jg .t_pos
    jl .t_neg1
    jmp .t2
.t_pos:
    mov ecx, 1
    jmp .t2
.t_neg1:
    mov edx, 1
.t2:
    cmp r11d, 0
    jg .t_pos2
    jl .t_neg2
    jmp .t3
.t_pos2:
    mov ecx, 1
    jmp .t3
.t_neg2:
    mov edx, 1
.t3:
    test eax, eax
    jg .t_pos3
    jl .t_neg3
    jmp .t_decide
.t_pos3:
    mov ecx, 1
    jmp .t_decide
.t_neg3:
    mov edx, 1
.t_decide:
    test ecx, ecx
    jz .plot
    test edx, edx
    jz .plot
    jmp .next
.plot:
    mov ecx, ebx
    mov edx, [rsp+16]
    GEN_PX ecx, edx, bts
.next:
    inc ebx
    jmp .px_loop
.px_done:
    mov ebx, [rsp+20]               ; px = minx
    inc dword [rsp+16]              ; py++
    jmp .py_loop
.done:
    add rsp, 24
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; ============================================================
; gen_pawn - pes: kruzok hlava, lichobeznikove telo, baza
; ============================================================
gen_pawn:
    mov edi, 0
    call gen_select
    mov edi, 8                      ; hlava
    mov esi, 5
    mov edx, 3
    call gen_fill_circle
    mov edi, 6                      ; telo (stupne)
    mov esi, 8
    mov edx, 4
    mov ecx, 2
    call gen_fill_rect
    mov edi, 5
    mov esi, 10
    mov edx, 6
    mov ecx, 2
    call gen_fill_rect
    mov edi, 4
    mov esi, 12
    mov edx, 8
    mov ecx, 1
    call gen_fill_rect
    mov edi, 3                      ; baza
    mov esi, 13
    mov edx, 10
    mov ecx, 2
    call gen_fill_rect
    ret

; ============================================================
; gen_knight - jazdec v profile: usko, hlava, nuchac, krk, baza
; ============================================================
gen_knight:
    mov edi, 1
    call gen_select
    mov edi, 7                      ; vertikalny blok (krk/hrud vzadu)
    mov esi, 5
    mov edx, 7
    mov ecx, 9
    call gen_fill_rect
    mov edi, 6                      ; hlava
    mov esi, 5
    mov edx, 3
    call gen_fill_circle
    mov edi, 5                      ; usko
    mov esi, 1
    mov edx, 7
    mov ecx, 1
    mov r8d, 6
    mov r9d, 3
    call gen_fill_triangle
    mov edi, 1                      ; nuchac/snos (ploche hranie vlavo)
    mov esi, 8
    mov edx, 1
    mov ecx, 11
    mov r8d, 6
    mov r9d, 9
    call gen_fill_triangle
    mov edi, 2                      ; prechod nuchac -> hlava
    mov esi, 8
    mov edx, 4
    mov ecx, 1
    call gen_fill_rect
    mov edi, 4                      ; brada/brisok (predny sklon)
    mov esi, 10
    mov edx, 4
    mov ecx, 3
    call gen_fill_rect
    mov edi, 3                      ; baza
    mov esi, 13
    mov edx, 11
    mov ecx, 2
    call gen_fill_rect
    mov edi, 4                      ; oko (2 px, vyclearovane)
    mov esi, 4
    mov edx, 4
    mov ecx, 5
    mov r8d, 1
    call gen_line
    ret

; ============================================================
; gen_bishop - strelec: mitra, pas, telo, baza, sikma strizka
; ============================================================
gen_bishop:
    mov edi, 2
    call gen_select
    mov edi, 8                      ; mitra
    mov esi, 1
    mov edx, 4
    mov ecx, 9
    mov r8d, 12
    mov r9d, 9
    call gen_fill_triangle
    mov edi, 4                      ; pas pod mitrou
    mov esi, 9
    mov edx, 8
    mov ecx, 1
    call gen_fill_rect
    mov edi, 5                      ; telo
    mov esi, 10
    mov edx, 6
    mov ecx, 2
    call gen_fill_rect
    mov edi, 4
    mov esi, 12
    mov edx, 8
    mov ecx, 1
    call gen_fill_rect
    mov edi, 3                      ; baza
    mov esi, 13
    mov edx, 10
    mov ecx, 2
    call gen_fill_rect
    mov edi, 5                      ; strizka cez mitru (clear)
    mov esi, 3
    mov edx, 11
    mov ecx, 8
    mov r8d, 1
    call gen_line
    ret

; ============================================================
; gen_rook - veza: 3 hradbove zubky, valec, baza
; ============================================================
gen_rook:
    mov edi, 3
    call gen_select
    mov edi, 3                      ; hradby (3 zubky)
    mov esi, 2
    mov edx, 2
    mov ecx, 3
    call gen_fill_rect
    mov edi, 7
    mov esi, 2
    mov edx, 2
    mov ecx, 3
    call gen_fill_rect
    mov edi, 11
    mov esi, 2
    mov edx, 2
    mov ecx, 3
    call gen_fill_rect
    mov edi, 4                      ; valec
    mov esi, 5
    mov edx, 8
    mov ecx, 8
    call gen_fill_rect
    mov edi, 3                      ; baza
    mov esi, 13
    mov edx, 10
    mov ecx, 2
    call gen_fill_rect
    ret

; ============================================================
; gen_queen - kralovna: 5-ostnova koruna, telo, baza
; ============================================================
gen_queen:
    mov edi, 4
    call gen_select
    mov edi, 2                      ; osten 1
    mov esi, 7
    mov edx, 6
    mov ecx, 7
    mov r8d, 4
    mov r9d, 2
    call gen_fill_triangle
    mov edi, 4                      ; osten 2
    mov esi, 7
    mov edx, 8
    mov ecx, 7
    mov r8d, 6
    mov r9d, 1
    call gen_fill_triangle
    mov edi, 6                      ; osten 3 (stredny, najvyssi)
    mov esi, 7
    mov edx, 10
    mov ecx, 7
    mov r8d, 8
    mov r9d, 1
    call gen_fill_triangle
    mov edi, 8                      ; osten 4
    mov esi, 7
    mov edx, 12
    mov ecx, 7
    mov r8d, 10
    mov r9d, 1
    call gen_fill_triangle
    mov edi, 10                     ; osten 5
    mov esi, 7
    mov edx, 14
    mov ecx, 7
    mov r8d, 12
    mov r9d, 2
    call gen_fill_triangle
    mov edi, 3                      ; pasmo spajajuce ostrohy do koruny
    mov esi, 5
    mov edx, 10
    mov ecx, 3
    call gen_fill_rect
    mov edi, 5                      ; telo
    mov esi, 7
    mov edx, 6
    mov ecx, 2
    call gen_fill_rect
    mov edi, 4
    mov esi, 9
    mov edx, 8
    mov ecx, 2
    call gen_fill_rect
    mov edi, 4
    mov esi, 11
    mov edx, 8
    mov ecx, 2
    call gen_fill_rect
    mov edi, 3                      ; baza
    mov esi, 13
    mov edx, 10
    mov ecx, 2
    call gen_fill_rect
    ret

; ============================================================
; gen_king - kral: kriz nad hlavou, kruh, telo, baza
; ============================================================
gen_king:
    mov edi, 5
    call gen_select
    mov edi, 7                      ; vertikala kriza
    mov esi, 1
    mov edx, 2
    mov ecx, 4
    call gen_fill_rect
    mov edi, 5                      ; horizntala kriza
    mov esi, 2
    mov edx, 6
    mov ecx, 2
    call gen_fill_rect
    mov edi, 8                      ; hlava
    mov esi, 7
    mov edx, 3
    call gen_fill_circle
    mov edi, 5                      ; telo
    mov esi, 10
    mov edx, 6
    mov ecx, 3
    call gen_fill_rect
    mov edi, 3                      ; baza
    mov esi, 13
    mov edx, 10
    mov ecx, 2
    call gen_fill_rect
    ret

; ============================================================
; 8x8 nativne masky (1 bajt/riadok, bit7 = lavy pixel)
; ============================================================

; gen_pawn8 - pes: kruzok hlava, zuzujuce sa telo, baza
gen_pawn8:
    mov edi, 0
    call gen_select8
    mov edi, 4                      ; hlava
    mov esi, 2
    mov edx, 1
    call gen_fill_circle
    mov edi, 3                      ; telo
    mov esi, 3
    mov edx, 2
    mov ecx, 2
    call gen_fill_rect
    mov edi, 2                      ; spodok tela
    mov esi, 5
    mov edx, 4
    mov ecx, 1
    call gen_fill_rect
    mov edi, 1                      ; baza
    mov esi, 6
    mov edx, 6
    mov ecx, 1
    call gen_fill_rect
    ret

; gen_knight8 - jazdec v profile: ucho, hlava, nuchac, krk, baza
gen_knight8:
    mov edi, 1
    call gen_select8
    mov edi, 2                      ; ucho
    mov esi, 0
    mov edx, 4
    mov ecx, 0
    mov r8d, 3
    mov r9d, 2
    call gen_fill_triangle
    mov edi, 3                      ; hlava
    mov esi, 3
    mov edx, 1
    call gen_fill_circle
    mov edi, 0                      ; nuchac (ploche hranie vlavo)
    mov esi, 3
    mov edx, 0
    mov ecx, 5
    mov r8d, 3
    mov r9d, 4
    call gen_fill_triangle
    mov edi, 1                      ; prechod nuchac-hlava
    mov esi, 3
    mov edx, 1
    mov ecx, 1
    call gen_fill_rect
    mov edi, 1                      ; hrud
    mov esi, 5
    mov edx, 2
    mov ecx, 1
    call gen_fill_rect
    mov edi, 3                      ; krk
    mov esi, 5
    mov edx, 2
    mov ecx, 2
    call gen_fill_rect
    mov edi, 3                      ; oddelenie ucha (clear)
    mov esi, 1
    mov edx, 3
    mov ecx, 1
    mov r8d, 1
    call gen_line
    mov edi, 4                      ; celist pred hlavou (clear)
    mov esi, 4
    mov edx, 4
    mov ecx, 4
    mov r8d, 1
    call gen_line
    mov edi, 1                      ; baza
    mov esi, 6
    mov edx, 6
    mov ecx, 1
    call gen_fill_rect
    ret

; gen_bishop8 - strelec: mitra, pas, telo, baza, sikma strizka
gen_bishop8:
    mov edi, 2
    call gen_select8
    mov edi, 4                      ; mitra
    mov esi, 0
    mov edx, 1
    mov ecx, 4
    mov r8d, 6
    mov r9d, 4
    call gen_fill_triangle
    mov edi, 2                      ; pas
    mov esi, 4
    mov edx, 5
    mov ecx, 1
    call gen_fill_rect
    mov edi, 3                      ; telo
    mov esi, 5
    mov edx, 3
    mov ecx, 1
    call gen_fill_rect
    mov edi, 1                      ; baza
    mov esi, 6
    mov edx, 6
    mov ecx, 1
    call gen_fill_rect
    mov edi, 2                      ; strizka cez mitru (clear)
    mov esi, 2
    mov edx, 5
    mov ecx, 3
    mov r8d, 1
    call gen_line
    ret

; gen_rook8 - veza: 3 hradby, valec, baza
gen_rook8:
    mov edi, 3
    call gen_select8
    mov edi, 1                      ; hradby
    mov esi, 0
    mov edx, 1
    mov ecx, 1
    call gen_fill_rect
    mov edi, 3
    mov esi, 0
    mov edx, 2
    mov ecx, 1
    call gen_fill_rect
    mov edi, 6
    mov esi, 0
    mov edx, 1
    mov ecx, 1
    call gen_fill_rect
    mov edi, 2                      ; valec
    mov esi, 1
    mov edx, 4
    mov ecx, 5
    call gen_fill_rect
    mov edi, 1                      ; baza
    mov esi, 6
    mov edx, 6
    mov ecx, 1
    call gen_fill_rect
    ret

; gen_queen8 - kralovna: 3-ostnova koruna, telo, baza
gen_queen8:
    mov edi, 4
    call gen_select8
    mov edi, 0                      ; osten 1
    mov esi, 2
    mov edx, 2
    mov ecx, 2
    mov r8d, 1
    mov r9d, 0
    call gen_fill_triangle
    mov edi, 2                      ; osten 2
    mov esi, 2
    mov edx, 4
    mov ecx, 2
    mov r8d, 3
    mov r9d, 0
    call gen_fill_triangle
    mov edi, 4                      ; osten 3
    mov esi, 2
    mov edx, 6
    mov ecx, 2
    mov r8d, 5
    mov r9d, 0
    call gen_fill_triangle
    mov edi, 6                      ; osten 4
    mov esi, 2
    mov edx, 8
    mov ecx, 2
    mov r8d, 7
    mov r9d, 0
    call gen_fill_triangle
    mov edi, 1                      ; pasmo koruny (spaja ostrohy)
    mov esi, 2
    mov edx, 6
    mov ecx, 1
    call gen_fill_rect
    mov edi, 2                      ; telo
    mov esi, 3
    mov edx, 4
    mov ecx, 3
    call gen_fill_rect
    mov edi, 1                      ; baza
    mov esi, 6
    mov edx, 6
    mov ecx, 1
    call gen_fill_rect
    ret

; gen_king8 - kral: kriz, hlava, telo, baza
gen_king8:
    mov edi, 5
    call gen_select8
    mov edi, 4                      ; vertikala kriza
    mov esi, 0
    mov edx, 1
    mov ecx, 3
    call gen_fill_rect
    mov edi, 2                      ; horizontala kriza
    mov esi, 1
    mov edx, 5
    mov ecx, 1
    call gen_fill_rect
    mov edi, 4                      ; hlava
    mov esi, 4
    mov edx, 1
    call gen_fill_circle
    mov edi, 3                      ; telo
    mov esi, 5
    mov edx, 2
    mov ecx, 1
    call gen_fill_rect
    mov edi, 1                      ; baza
    mov esi, 6
    mov edx, 6
    mov ecx, 1
    call gen_fill_rect
    ret

; ============================================================
; piece_gen_dump - tlaci 6 masiek ako #/. (len pri debug=1)
; ============================================================
piece_gen_dump:
    push rbx
    push r12
    push r13
    push r14
    DUMP_MASK dump_name_p, 0
    DUMP_MASK dump_name_n, 1
    DUMP_MASK dump_name_b, 2
    DUMP_MASK dump_name_r, 3
    DUMP_MASK dump_name_q, 4
    DUMP_MASK dump_name_k, 5
    DUMP_MASK8 dump8_name_p, 0
    DUMP_MASK8 dump8_name_n, 1
    DUMP_MASK8 dump8_name_b, 2
    DUMP_MASK8 dump8_name_r, 3
    DUMP_MASK8 dump8_name_q, 4
    DUMP_MASK8 dump8_name_k, 5
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ============================================================
; piece_gen_init - vygeneruje vsetkych 6 figuriek
; ============================================================
piece_gen_init:
    call gen_pawn
    call gen_knight
    call gen_bishop
    call gen_rook
    call gen_queen
    call gen_king
    call gen_pawn8
    call gen_knight8
    call gen_bishop8
    call gen_rook8
    call gen_queen8
    call gen_king8
    cmp byte [debug], 0
    je .done
    call piece_gen_dump
.done:
    ret
