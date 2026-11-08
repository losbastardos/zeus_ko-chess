; ============================================================
; Copyright (c) 2026 Marek Suchy <marek.suchy@gmail.com>
; Vsetky prava vyhradene / All rights reserved.
; ============================================================

; ============================================================
; gfx/gfx.asm - framebuffer rendering a graficka slucka
; ============================================================

%include "chess.inc"

DEFAULT REL

section .data

msg_gfx_error:
    db "Chyba: nepodarilo sa inicializovat framebuffer/grafika.", 10, 0
msg_gfx_error_len equ $ - msg_gfx_error - 1

msg_gfx_fb_open:
    db "Chyba: nepodarilo sa otvorit framebuffer.", 10, 0
msg_gfx_fb_open_len equ $ - msg_gfx_fb_open - 1

msg_gfx_sysfs:
    db "Chyba: nepodarilo sa nacitat rozlisenie framebufferu.", 10, 0
msg_gfx_sysfs_len equ $ - msg_gfx_sysfs - 1

msg_gfx_bmp:
    db "Chyba: nepodarilo sa nacitat BMP figurka.", 10, 0
msg_gfx_bmp_len equ $ - msg_gfx_bmp - 1

msg_gfx_mouse:
    db "Chyba: nepodarilo sa otvorit mys.", 10, 0
msg_gfx_mouse_len equ $ - msg_gfx_mouse - 1

msg_text_return:
    db "Navrat do textoveho rezimu.", 10, 0
msg_text_return_len equ $ - msg_text_return - 1

msg_gfx_prompt:
    db "Gfx rezim: klikni zdroj a ciel. 'text' v terminali = navrat.", 10, 0
msg_gfx_prompt_len equ $ - msg_gfx_prompt - 1

sysfs_virtual_size:
    db "/sys/class/graphics/fb0/virtual_size", 0
sysfs_bpp:
    db "/sys/class/graphics/fb0/bits_per_pixel", 0

; ============================================================
section .text

global gfx_init, gfx_close, gfx_run, gfx_refresh, gfx_square_from_xy

extern config_get, parse_int
extern generate_all_moves, parse_user_move, find_move, apply_move, update_position_state, compute_hash, record_hash
extern print_move, print_newline
extern search_best_move, book_lookup
extern mouse_init, mouse_read_event

extern config_buf
extern board, side, board_flip, move_list, move_count, search_depth, move_buf, move_buf_len, engine_side
extern fb_ptr, fb_size, fb_width, fb_height, fb_bpp, fb_stride, fb_bytes
extern square_size, board_offset_x, board_offset_y
extern light_col, dark_col, highlight_col, bg_col
extern assets_path, mouse_device, mouse_fd, mouse_x, mouse_y, mouse_btn_left
extern gfx_mode, gfx_initialized, gfx_highlight_sq
extern bmp_ptrs, bmp_sizes, bmp_widths, bmp_heights, gfx_fb_fd
extern piece_name_ptrs
extern key_framebuffer, default_framebuffer
extern key_square_size, default_square_size
extern key_light_square, default_light_square
extern key_dark_square, default_dark_square
extern key_highlight, default_highlight
extern key_assets, default_assets
extern key_mouse, default_mouse

; ============================================================
; print_msg - vypise C-string na stdout
; Vstup: rdi = ukazatel, esi = dlzka
; ============================================================
print_msg:
    push rax
    push rdx
    mov rax, SYS_WRITE
    mov rdx, rsi
    mov rsi, rdi
    mov rdi, STDOUT
    syscall
    pop rdx
    pop rax
    ret

; ============================================================
; str_copy - kopiruje C-string z rsi do rdi, max rcx
; ============================================================
str_copy:
    push rax
    push rbx
    xor rbx, rbx
.loop:
    cmp rbx, rcx
    jge .done
    mov al, [rsi + rbx]
    mov [rdi + rbx], al
    test al, al
    jz .done
    inc rbx
    jmp .loop
.done:
    pop rbx
    pop rax
    ret

; ============================================================
; str_append - pripoji C-string z rsi na koniec retazca v rdi
; ============================================================
str_append:
    push rax
    push rbx
    push rcx
    push rdx
    mov rcx, rdi
.len1:
    mov al, [rcx]
    test al, al
    jz .copy2
    inc rcx
    jmp .len1
.copy2:
    xor rdx, rdx
.loop:
    mov al, [rsi + rdx]
    mov [rcx + rdx], al
    test al, al
    jz .done
    inc rdx
    jmp .loop
.done:
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

; ============================================================
; parse_int_ptr - obal na parse_int (rdi -> rsi)
; ============================================================
parse_int_ptr:
    mov rsi, rdi
    jmp parse_int

; ============================================================
; parse_color - prevedie "0xRRGGBB" alebo "RRGGBB" na BGRA
; Vstup: rdi = ukazatel
; Vystup: eax = farba (BGRA byte order, alpha = 0xFF)
; ============================================================
parse_color:
    push rbx
    push rcx
    push rdx
    mov rsi, rdi

    ; preskoc 0x/0X
    movzx rax, byte [rsi]
    cmp al, '0'
    jne .parse
    movzx rax, byte [rsi+1]
    cmp al, 'x'
    je .skip
    cmp al, 'X'
    je .skip
    jmp .parse
.skip:
    add rsi, 2
.parse:
    xor rax, rax
    xor rcx, rcx
.loop:
    movzx rbx, byte [rsi + rcx]
    test rbx, rbx
    jz .convert
    cmp bl, '0'
    jl .convert
    cmp bl, '9'
    jle .digit
    cmp bl, 'a'
    jl .maybe_upper
    cmp bl, 'f'
    jle .lower
.maybe_upper:
    cmp bl, 'A'
    jl .convert
    cmp bl, 'F'
    jle .upper
    jmp .convert
.digit:
    sub bl, '0'
    jmp .add
.lower:
    sub bl, 'a' - 10
    jmp .add
.upper:
    sub bl, 'A' - 10
.add:
    shl rax, 4
    add rax, rbx
    inc rcx
    jmp .loop
.convert:
    ; rax = 0x00RRGGBB -> BGRA 0xFFRRGGBB (little-endian word)
    mov rbx, rax
    and rbx, 0x0000FF       ; B
    mov rcx, rax
    and rcx, 0x00FF00       ; G
    mov rdx, rax
    and rdx, 0xFF0000       ; R
    mov eax, 0xFF000000
    or rax, rdx
    or rax, rcx
    or rax, rbx
    pop rdx
    pop rcx
    pop rbx
    ret

; ============================================================
; read_file_to_buf - otvori subor, nacita max rdx bajtov
; Vstup: rdi = nazov, rsi = buffer, rdx = max
; Vystup: rax = nacitane bajty, -1 ak chyba
; ============================================================
read_file_to_buf:
    push rbx
    push r12
    push r13
    push r14

    mov r12, rsi
    mov r13, rdx

    mov rax, 2
    xor rsi, rsi
    syscall
    cmp rax, 0
    jl .error
    mov r14, rax

    xor rbx, rbx
.read_loop:
    cmp rbx, r13
    jge .read_done
    mov rax, 0
    mov rdi, r14
    lea rsi, [r12 + rbx]
    mov rdx, r13
    sub rdx, rbx
    syscall
    cmp rax, 0
    jle .read_done
    add rbx, rax
    jmp .read_loop

.read_done:
    mov rax, 3
    mov rdi, r14
    syscall
    mov rax, rbx
    jmp .done

.error:
    mov rax, -1
.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ============================================================
; read_fb_size - nacita virtual_size do fb_width/height
; ============================================================
read_fb_size:
    push rbx
    push r12
    push r13

    sub rsp, 64
    lea rdi, [sysfs_virtual_size]
    lea rsi, [rsp]
    mov rdx, 63
    call read_file_to_buf
    cmp rax, 0
    jl .error
    mov byte [rsp + rax], 0

    lea rsi, [rsp]
    xor r12, r12
    xor r13, r13
.width_loop:
    movzx rbx, byte [rsi + r12]
    test rbx, rbx
    jz .width_done
    cmp bl, ','
    je .width_done
    cmp bl, '0'
    jl .error
    cmp bl, '9'
    jg .error
    sub bl, '0'
    imul r13, 10
    add r13, rbx
    inc r12
    jmp .width_loop
.width_done:
    mov [fb_width], r13d
    test rbx, rbx
    jz .height_done
    inc r12
.height_loop:
    movzx rbx, byte [rsi + r12]
    test rbx, rbx
    jz .height_done
    cmp bl, 10
    je .height_done
    cmp bl, '0'
    jl .error
    cmp bl, '9'
    jg .error
    sub bl, '0'
    imul r13, 10
    add r13, rbx
    inc r12
    jmp .height_loop
.height_done:
    mov [fb_height], r13d
    add rsp, 64
    xor rax, rax
    jmp .done

.error:
    add rsp, 64
    mov rax, 1
.done:
    pop r13
    pop r12
    pop rbx
    ret

; ============================================================
; read_fb_bpp - nacita bits_per_pixel
; ============================================================
read_fb_bpp:
    push rbx
    sub rsp, 32
    lea rdi, [sysfs_bpp]
    lea rsi, [rsp]
    mov rdx, 31
    call read_file_to_buf
    cmp rax, 0
    jl .error
    mov byte [rsp + rax], 0
    lea rdi, [rsp]
    call parse_int_ptr
    cmp rax, 16
    jl .default_bpp
    cmp rax, 32
    jg .default_bpp
    mov [fb_bpp], eax
    add rsp, 32
    xor rax, rax
    pop rbx
    ret
.default_bpp:
    mov dword [fb_bpp], 32
    add rsp, 32
    xor rax, rax
    pop rbx
    ret
.error:
    add rsp, 32
    mov rax, 1
    pop rbx
    ret

; ============================================================
; open_mmap_fb - otvori framebuffer a mmap
; Vstup: rdi = cesta
; Vystup: rax = 0 OK, 1 chyba
; ============================================================
open_mmap_fb:
    push rbx
    push r12
    push r13

    mov rax, 2
    mov rsi, 2          ; O_RDWR
    syscall
    cmp rax, 0
    jl .error
    mov r12, rax

    mov ebx, [fb_bpp]
    add ebx, 7
    shr ebx, 3
    mov [fb_bytes], ebx

    mov eax, [fb_width]
    mul ebx
    mov [fb_stride], eax

    mov eax, [fb_stride]
    mov ebx, [fb_height]
    mul ebx
    mov r13, rax
    mov [fb_size], rax

    mov rax, 9
    xor rdi, rdi
    mov rsi, r13
    mov rdx, 3          ; PROT_READ | PROT_WRITE
    mov r10, 1          ; MAP_SHARED
    mov r8, r12
    xor r9, r9
    syscall
    cmp rax, 0
    jl .close_error
    mov rbx, rax

    mov rax, 3
    mov rdi, r12
    syscall

    mov [fb_ptr], rbx
    mov [gfx_fb_fd], r12d
    xor rax, rax
    jmp .done

.close_error:
    mov r13, rax
    mov rax, 3
    mov rdi, r12
    syscall
    mov rax, r13
.error:
    mov rax, 1
.done:
    pop r13
    pop r12
    pop rbx
    ret

; ============================================================
; draw_rect - vyplni obdlznik farbou
; Vstup: r12=x, r13=y, r14=w, r15=h, ebx=farba
; ============================================================
draw_rect:
    push rax
    push rcx
    push rdx
    push rsi
    push rdi
    push r8
    push r9

    cmp r14, 0
    jle .done
    cmp r15, 0
    jle .done

    mov rdi, [fb_ptr]
    xor rax, rax
    mov eax, [fb_stride]
    mul r13d
    add rdi, rax
    xor rax, rax
    mov eax, [fb_bytes]
    mul r12d
    add rdi, rax

    mov r9, r15
    mov eax, ebx
.row_loop:
    mov rcx, r14
    rep stosd
    add rdi, [fb_stride]
    dec r9
    jnz .row_loop

.done:
    pop r9
    pop r8
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rax
    ret

; ============================================================
; draw_bmp - blitne BMP figurku na framebuffer
; Vstup: r12 = x, r13 = y, r14 = index BMP (0..11)
; ============================================================
draw_bmp:
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r8
    push r9
    push r10
    push r11

    lea rsi, [bmp_ptrs]
    mov rdi, [rsi + r14*8]
    test rdi, rdi
    jz .done

    mov ebx, [bmp_widths + r14*4]
    mov ecx, [bmp_heights + r14*4]

    ; BMP rows are bottom-up
    xor r8, r8
.row_loop:
    cmp r8d, ecx
    jge .done

    mov r9d, ecx
    dec r9d
    sub r9d, r8d

    mov eax, ebx
    imul eax, 3
    add eax, 3
    and eax, 0xFFFFFFFC
    mov r10d, eax

    mov eax, r9d
    mul r10d
    lea rsi, [rdi + 54]
    add rsi, rax

    mov r15, [fb_ptr]
    mov eax, [fb_stride]
    mov r11d, r13d
    add r11d, r8d
    mul r11d
    add r15, rax
    mov eax, r12d
    mov r11d, [fb_bytes]
    mul r11d
    add r15, rax

    xor r9, r9
.col_loop:
    cmp r9d, ebx
    jge .next_row

    mov rcx, r9
    shl rcx, 1
    add rcx, r9

    movzx rax, byte [rsi + rcx + 0]
    movzx rdx, byte [rsi + rcx + 1]
    movzx r10, byte [rsi + rcx + 2]

    cmp rax, 0xFF
    jne .write
    cmp rdx, 0
    jne .write
    cmp r10, 0xFF
    jne .write
    jmp .skip

.write:
    shl r10, 16
    shl rdx, 8
    or rax, rdx
    or rax, r10
    mov ebx, 0xFF000000
    or rax, rbx
    mov [r15 + r9*4], eax

.skip:
    inc r9
    jmp .col_loop

.next_row:
    inc r8
    jmp .row_loop

.done:
    pop r11
    pop r10
    pop r9
    pop r8
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

; ============================================================
; load_bmp_index - nacita a nacachuje BMP figurku
; Vstup: r12 = index 0..11
; ============================================================
load_bmp_index:
    push rbx
    push r12
    push r13
    push r14
    push r15

    sub rsp, 128
    mov rdi, rsp
    lea rsi, [assets_path]
    mov rcx, 127
    call str_copy

    mov rdi, rsp
.len:
    mov al, [rdi]
    test al, al
    jz .check_slash
    inc rdi
    jmp .len
.check_slash:
    mov al, [rdi - 1]
    cmp al, '/'
    je .append
    mov byte [rdi], '/'
    mov byte [rdi + 1], 0
.append:
    lea rdi, [rsp]
    lea rsi, [piece_name_ptrs]
    mov rax, [rsi + r12*8]
    mov rsi, rax
    call str_append

    mov rdi, rsp
    mov rax, 2
    xor rsi, rsi
    syscall
    cmp rax, 0
    jl .error
    mov r13, rax

    mov rax, 8
    mov rdi, r13
    xor rsi, rsi
    mov rdx, 2
    syscall
    cmp rax, 0
    jle .close_error
    mov r14, rax

    mov rax, 8
    mov rdi, r13
    xor rsi, rsi
    xor rdx, rdx
    syscall

    mov rax, 9
    xor rdi, rdi
    mov rsi, r14
    mov dl, 1
    mov r10, 2
    mov r8, r13
    xor r9, r9
    syscall
    cmp rax, 0
    jl .close_error
    mov r15, rax

    mov rax, 3
    mov rdi, r13
    syscall

    movzx rax, byte [r15]
    cmp al, 'B'
    jne .error
    movzx rax, byte [r15 + 1]
    cmp al, 'M'
    jne .error

    mov eax, [r15 + 0x12]
    mov [bmp_widths + r12*4], eax
    mov eax, [r15 + 0x16]
    test eax, eax
    jns .height_ok
    neg eax
.height_ok:
    mov [bmp_heights + r12*4], eax

    lea rsi, [bmp_ptrs]
    mov [rsi + r12*8], r15
    lea rsi, [bmp_sizes]
    mov [rsi + r12*8], r14

    add rsp, 128
    xor rax, rax
    jmp .done

.close_error:
    mov rax, 3
    mov rdi, r13
    syscall
.error:
    add rsp, 128
    mov rax, 1
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ============================================================
; load_all_bmps - nacita vsetkych 12 figurok
; ============================================================
load_all_bmps:
    push r12
    xor r12, r12
.loop:
    cmp r12, 12
    jge .done
    call load_bmp_index
    test rax, rax
    jnz .fail
    inc r12
    jmp .loop
.fail:
    mov rax, 1
.done:
    pop r12
    ret

; ============================================================
; gfx_close - zatvori framebuffer a BMP
; ============================================================
gfx_close:
    push rax
    push rbx
    push r12

    mov rax, [fb_ptr]
    test rax, rax
    jz .bmps
    mov r12, rax
    mov rax, 11
    mov rdi, r12
    mov rsi, [fb_size]
    syscall
    mov qword [fb_ptr], 0

.bmps:
    xor r12, r12
.bmp_loop:
    cmp r12, 12
    jge .close_mouse
    lea rbx, [bmp_ptrs]
    mov rax, [rbx + r12*8]
    test rax, rax
    jz .next_bmp
    mov rdi, rax
    mov rsi, [bmp_sizes + r12*8]
    mov rax, 11
    syscall
    mov qword [rbx + r12*8], 0
.next_bmp:
    inc r12
    jmp .bmp_loop

.close_mouse:
    mov rax, [mouse_fd]
    test rax, rax
    jz .done
    mov rdi, rax
    mov rax, 3
    syscall
    mov qword [mouse_fd], 0

.done:
    mov byte [gfx_initialized], 0
    mov byte [gfx_mode], 0
    pop r12
    pop rbx
    pop rax
    ret

; ============================================================
; gfx_init - inicializuje grafiku podla configu
; ============================================================
gfx_init:
    push rbx
    push r12

    mov byte [gfx_initialized], 0
    mov byte [gfx_mode], 0
    mov byte [gfx_highlight_sq], 255

    ; assets path
    lea rdi, [key_assets]
    lea rsi, [default_assets]
    call config_get
    lea rdi, [assets_path]
    mov rsi, rax
    mov rcx, 63
    call str_copy

    ; mouse device
    lea rdi, [key_mouse]
    lea rsi, [default_mouse]
    call config_get
    lea rdi, [mouse_device]
    mov rsi, rax
    mov rcx, 63
    call str_copy

    ; square size
    lea rdi, [key_square_size]
    lea rsi, [default_square_size]
    call config_get
    mov rdi, rax
    call parse_int_ptr
    cmp rax, 20
    jl .size_default
    cmp rax, 400
    jle .size_ok
.size_default:
    mov rax, 100
.size_ok:
    mov [square_size], eax

    ; colors
    lea rdi, [key_light_square]
    lea rsi, [default_light_square]
    call config_get
    mov rdi, rax
    call parse_color
    mov [light_col], eax

    lea rdi, [key_dark_square]
    lea rsi, [default_dark_square]
    call config_get
    mov rdi, rax
    call parse_color
    mov [dark_col], eax

    lea rdi, [key_highlight]
    lea rsi, [default_highlight]
    call config_get
    mov rdi, rax
    call parse_color
    mov [highlight_col], eax

    ; read fb size & bpp
    call read_fb_size
    test rax, rax
    jnz .error
    call read_fb_bpp
    test rax, rax
    jnz .error

    ; open framebuffer
    lea rdi, [key_framebuffer]
    lea rsi, [default_framebuffer]
    call config_get
    mov rdi, rax
    call open_mmap_fb
    test rax, rax
    jnz .fb_error

    ; center board
    mov eax, [square_size]
    shl eax, 3
    mov r12d, eax
    mov eax, [fb_width]
    sub eax, r12d
    shr eax, 1
    mov [board_offset_x], eax
    mov eax, [fb_height]
    sub eax, r12d
    shr eax, 1
    mov [board_offset_y], eax

    ; load bmps
    call load_all_bmps
    test rax, rax
    jnz .bmp_error

    ; init mouse
    call mouse_init
    test rax, rax
    jnz .mouse_error

    mov byte [gfx_initialized], 1
    mov byte [gfx_mode], 1
    xor rax, rax
    jmp .done

.bmp_error:
    mov rdi, msg_gfx_bmp
    mov rsi, msg_gfx_bmp_len
    call print_msg
    call gfx_close
    mov rax, 1
    jmp .done

.mouse_error:
    mov rdi, msg_gfx_mouse
    mov rsi, msg_gfx_mouse_len
    call print_msg
    call gfx_close
    mov rax, 1
    jmp .done

.fb_error:
    mov rdi, msg_gfx_fb_open
    mov rsi, msg_gfx_fb_open_len
    call print_msg
    call gfx_close
    mov rax, 1
    jmp .done

.error:
    mov rdi, msg_gfx_error
    mov rsi, msg_gfx_error_len
    call print_msg
    call gfx_close
    mov rax, 1

.done:
    pop r12
    pop rbx
    ret

; ============================================================
; screen_to_board - prevedie screen row,col na board square
; Vstup: r12 = row, r13 = col
; Vystup: eax = square 0..63
; ============================================================
screen_to_board:
    cmp byte [board_flip], 0
    je .white_view
    ; black view: sq = row*8 + (7-col)
    mov eax, r12d
    shl eax, 3
    mov ecx, 7
    sub ecx, r13d
    add eax, ecx
    ret
.white_view:
    ; white view: sq = (7-row)*8 + col
    mov ecx, 7
    sub ecx, r12d
    shl ecx, 3
    add ecx, r13d
    mov eax, ecx
    ret

; ============================================================
; gfx_draw_board - nakresli sachovnicu
; ============================================================
gfx_draw_board:
    push rax
    push rbx
    push rcx
    push rdx
    push r12
    push r13
    push r14
    push r15

    ; clear background
    xor r12, r12
    xor r13, r13
    mov r14d, [fb_width]
    mov r15d, [fb_height]
    xor ebx, ebx
    call draw_rect

    xor r12, r12
.rank_loop:
    cmp r12, 8
    jge .done

    xor r13, r13
.file_loop:
    cmp r13, 8
    jge .next_rank

    ; board square pre toto screen policko
    call screen_to_board
    mov r15d, eax

    ; farba policka
    mov eax, r12d
    add eax, r13d
    test al, 1
    jz .light
    mov ebx, [dark_col]
    jmp .color_ok
.light:
    mov ebx, [light_col]
.color_ok:

    cmp r15b, [gfx_highlight_sq]
    jne .no_highlight
    mov ebx, [highlight_col]
.no_highlight:

    ; screen coords
    mov r10d, [board_offset_x]
    mov eax, [square_size]
    mul r13d
    add r10d, eax
    mov r11d, [board_offset_y]
    mov eax, [square_size]
    mul r12d
    add r11d, eax

    push r10
    push r11
    push r12
    push r13
    push r15
    mov r12d, r10d
    mov r13d, r11d
    mov r14d, [square_size]
    mov r15d, [square_size]
    call draw_rect
    pop r15
    pop r13
    pop r12
    pop r11
    pop r10

    ; piece on this square
    movzx ecx, byte [board + r15]
    test ecx, ecx
    jz .next_file

    mov edx, ecx
    and edx, COLOR_MASK
    shr edx, 3
    and ecx, PIECE_MASK
    dec ecx
    mov eax, edx
    imul eax, 6
    add eax, ecx

    mov r8d, [square_size]
    sub r8d, [bmp_widths + eax*4]
    shr r8d, 1
    add r8d, r10d
    mov r9d, [square_size]
    sub r9d, [bmp_heights + eax*4]
    shr r9d, 1
    add r9d, r11d

    push r12
    push r13
    push r14
    push r15
    push rax
    mov r12d, r8d
    mov r13d, r9d
    mov r14d, eax
    call draw_bmp
    pop rax
    pop r15
    pop r14
    pop r13
    pop r12

.next_file:
    inc r13
    jmp .file_loop

.next_rank:
    inc r12
    jmp .rank_loop

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

; ============================================================
; gfx_square_from_xy - prevedie mys x,y na index policka
; Vstup: r12 = x, r13 = y
; Vystup: eax = 0..63 alebo -1
; ============================================================
gfx_square_from_xy:
    push r14
    push r15

    mov eax, r12d
    sub eax, [board_offset_x]
    cmp eax, 0
    jl .invalid
    mov ecx, [square_size]
    xor edx, edx
    div ecx
    cmp eax, 8
    jge .invalid
    mov r14d, eax

    mov eax, r13d
    sub eax, [board_offset_y]
    cmp eax, 0
    jl .invalid
    mov ecx, [square_size]
    xor edx, edx
    div ecx
    cmp eax, 8
    jge .invalid
    mov r15d, eax

    mov r12d, r15d
    mov r13d, r14d
    call screen_to_board
    pop r15
    pop r14
    ret

.invalid:
    pop r15
    pop r14
    mov rax, -1
    ret

; ============================================================
; gfx_refresh - prekresli celu dosku
; ============================================================
gfx_refresh:
    push rax
    call gfx_draw_board
    pop rax
    ret

; ============================================================
; gfx_get_click - caka na lave kliknutie, vrati x,y
; Vystup: eax = x, ebx = y, -1 ak text/exit
; ============================================================
gfx_get_click:
    push r12
    push r13
    push r14
    push r15

    ; kazde volanie musi cakat na novy klik, nie zdedit stary stlaceny stav
    mov byte [mouse_btn_left], 0

.loop:
    sub rsp, 32
    mov eax, [mouse_fd]
    mov dword [rsp], 0
    mov word [rsp + 4], 1       ; POLLIN
    mov word [rsp + 6], 0
    mov dword [rsp + 8], eax
    mov word [rsp + 12], 1
    mov word [rsp + 14], 0

    mov rax, 7                  ; SYS_poll
    mov rdi, rsp
    mov rsi, 2
    mov rdx, -1
    syscall
    cmp rax, 0
    jle .next_loop

    ; check stdin revents at rsp+6
    movzx rax, word [rsp + 6]
    test al, 1                  ; POLLIN
    jz .mouse_ready

    ; read one full line from terminal (line-buffered)
    xor r12, r12
.stdin_read_loop:
    mov rax, SYS_READ
    mov rdi, STDIN
    lea rsi, [move_buf + r12]
    mov rdx, 1
    syscall
    cmp rax, 1
    jne .stdin_done
    movzx r14, byte [move_buf + r12]
    cmp r14, 10
    je .stdin_done
    inc r12
    cmp r12, 31
    jl .stdin_read_loop

.stdin_consume:
    mov rax, SYS_READ
    mov rdi, STDIN
    lea rsi, [move_buf + 31]
    mov rdx, 1
    syscall
    cmp rax, 1
    jne .stdin_done
    movzx r14, byte [move_buf + 31]
    cmp r14, 10
    jne .stdin_consume

.stdin_done:
    mov [move_buf_len], r12
    mov byte [move_buf + r12], 0

    ; command: q / text / exit / quit
    cmp qword [move_buf_len], 1
    jne .check_len4
    cmp byte [move_buf], 'q'
    je .text_return
    jmp .mouse_ready

.check_len4:
    cmp qword [move_buf_len], 4
    jne .mouse_ready

    cmp byte [move_buf], 't'
    jne .check_exit
    cmp byte [move_buf + 1], 'e'
    jne .typed_move
    cmp byte [move_buf + 2], 'x'
    jne .typed_move
    cmp byte [move_buf + 3], 't'
    je .text_return
    jmp .typed_move

.check_exit:
    cmp byte [move_buf], 'e'
    jne .check_quit
    cmp byte [move_buf + 1], 'x'
    jne .typed_move
    cmp byte [move_buf + 2], 'i'
    jne .typed_move
    cmp byte [move_buf + 3], 't'
    je .text_return
    jmp .typed_move

.check_quit:
    cmp byte [move_buf], 'q'
    jne .typed_move
    cmp byte [move_buf + 1], 'u'
    jne .typed_move
    cmp byte [move_buf + 2], 'i'
    jne .typed_move
    cmp byte [move_buf + 3], 't'
    je .text_return

.typed_move:
    mov rax, -2
    mov rbx, -2
    jmp .done

.mouse_ready:
    movzx rax, word [rsp + 14]
    test al, 1
    jz .next_loop
    add rsp, 32

    call mouse_read_event
    cmp byte [mouse_btn_left], 1
    jne .loop

    mov eax, [mouse_x]
    mov ebx, [mouse_y]
    jmp .done

.next_loop:
    add rsp, 32
    jmp .loop

.text_return:
    add rsp, 32
    mov rax, -1
    mov rbx, -1

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    ret

; ============================================================
; gfx_human_turn - caka na tah hraca cez mys
; Vystup: ax = tah, 0 ak navrat do textu/exit
; ============================================================
gfx_human_turn:
    push rbx
    push r12
    push r13
    push r14

.wait_source:
    mov byte [gfx_highlight_sq], 255
.first_click:
    call gfx_get_click
    cmp rax, -1
    je .text_return
    cmp rax, -2
    je .typed_move
    mov r12, rax
    mov r13, rbx
    call gfx_square_from_xy
    cmp rax, -1
    je .first_click
    mov r14d, eax

    ; zdroj musi byt vlastna figura strany na tahu
    movzx eax, byte [board + r14]
    test al, al
    jz .first_click
    movzx ecx, byte [side]
    shl cl, 3
    and al, COLOR_MASK
    cmp al, cl
    jne .first_click

    mov [gfx_highlight_sq], r14b
    call gfx_refresh

.second_click:
    call gfx_get_click
    cmp rax, -1
    je .text_return
    cmp rax, -2
    je .typed_move
    mov r12, rax
    mov r13, rbx
    call gfx_square_from_xy
    cmp rax, -1
    je .second_click
    mov r15d, eax

    movzx eax, byte [board + r15]
    test al, al
    jz .second_target_ok
    movzx ecx, byte [side]
    shl cl, 3
    and al, COLOR_MASK
    cmp al, cl
    jne .second_target_ok
    mov r14d, r15d
    mov [gfx_highlight_sq], r14b
    call gfx_refresh
    jmp .second_click

.second_target_ok:

    mov byte [gfx_highlight_sq], 255
    call gfx_refresh

    ; build move
    mov eax, r14d
    mov ecx, r15d
    shl ecx, 6
    or eax, ecx
    push rax

    call generate_all_moves
    pop rax
    call find_move
    test ax, ax
    jz .illegal

    jmp .done

.typed_move:
    call parse_user_move
    call generate_all_moves
    call find_move
    test ax, ax
    jz .wait_source
    mov byte [gfx_highlight_sq], 255
    call gfx_refresh
    jmp .done

.illegal:
    jmp .wait_source

.text_return:
    xor rax, rax
.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ============================================================
; gfx_engine_turn - engine zahrá a vykresli
; ============================================================
gfx_engine_turn:
    push rax

    call book_lookup
    test rax, rax
    jnz .do_move

    movzx rdi, byte [search_depth]
    call search_best_move

.do_move:
    push rax
    call print_move
    call print_newline
    pop rax
    call apply_move
    call update_position_state
    call compute_hash
    call record_hash
    call gfx_refresh

    pop rax
    ret

; ============================================================
; gfx_run - hlavna graficka slucka
; ============================================================
gfx_run:
    push rax

    mov rdi, msg_gfx_prompt
    mov rsi, msg_gfx_prompt_len
    call print_msg

.loop:
    call gfx_refresh

    ; rovnaka logika ako v text mode: engine hra podla engine_side
    movzx rax, byte [engine_side]
    cmp rax, 2
    je .engine
    cmp rax, 3
    je .human
    movzx rcx, byte [side]
    cmp rax, rcx
    je .engine

.human:

    call gfx_human_turn
    test ax, ax
    jz .done
    call apply_move
    call update_position_state
    call compute_hash
    call record_hash
    jmp .loop

.engine:
    call gfx_engine_turn
    jmp .loop

.done:
    call gfx_close
    mov rdi, msg_text_return
    mov rsi, msg_text_return_len
    call print_msg

    pop rax
    ret