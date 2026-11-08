; ============================================================
; Copyright (c) 2026 Marek Suchy <marek.suchy@gmail.com>
; Vsetky prava vyhradene / All rights reserved.
; ============================================================

; ============================================================
; gfx/sdl.asm - SDL backend pre graficke rozhranie
; ============================================================

%include "chess.inc"

DEFAULT REL

section .data

mode_rb: db "rb", 0

msg_sdl_error:
    db "Chyba: SDL inicializacia zlyhala.", 10, 0
msg_sdl_error_len equ $ - msg_sdl_error - 1

msg_sdl_window:
    db "Chyba: SDL okno sa nepodarilo vytvorit.", 10, 0
msg_sdl_window_len equ $ - msg_sdl_window - 1

msg_sdl_bmp:
    db "Chyba: SDL nacitanie BMP figury zlyhalo.", 10, 0
msg_sdl_bmp_len equ $ - msg_sdl_bmp - 1

msg_sdl_return:
    db "Navrat do textoveho rezimu.", 10, 0
msg_sdl_return_len equ $ - msg_sdl_return - 1

msg_sdl_prompt:
    db "SDL rezim: klikni zdroj a ciel. Esc/q = navrat.", 10, 0
msg_sdl_prompt_len equ $ - msg_sdl_prompt - 1

msg_dbg_src:
    db "[dbg] src sq=", 0
msg_dbg_src_len equ $ - msg_dbg_src - 1

msg_dbg_dst:
    db "[dbg] dst sq=", 0
msg_dbg_dst_len equ $ - msg_dbg_dst - 1

msg_dbg_move:
    db "[dbg] move from=", 0
msg_dbg_move_len equ $ - msg_dbg_move - 1

msg_dbg_to:
    db " to=", 0
msg_dbg_to_len equ $ - msg_dbg_to - 1

msg_dbg_found:
    db "[dbg] found move=", 0
msg_dbg_found_len equ $ - msg_dbg_found - 1

msg_dbg_illegal:
    db "[dbg] illegal move", 10, 0
msg_dbg_illegal_len equ $ - msg_dbg_illegal - 1

msg_dbg_click_x:
    db "[dbg] click x=", 0
msg_dbg_click_x_len equ $ - msg_dbg_click_x - 1

msg_dbg_click_y:
    db " y=", 0
msg_dbg_click_y_len equ $ - msg_dbg_click_y - 1

window_title:
    db "Sachovy engine", 0

; ============================================================
section .bss

global sdl_window, sdl_surface
sdl_window:     resq 1
sdl_surface:    resq 1
sdl_bmps:       resq 12
sdl_light:      resd 1
sdl_dark:       resd 1
sdl_highlight:  resd 1

; ============================================================
section .text

global sdl_gfx_init, sdl_gfx_close, sdl_gfx_run, sdl_gfx_refresh

extern config_get, parse_int
extern generate_all_moves, parse_user_move, find_move, apply_move, update_position_state, compute_hash, record_hash
extern print_move, print_newline, print_number
extern search_best_move, book_lookup

extern board, side, board_flip, search_depth, engine_side
extern debug
extern move_buf, move_buf_len
extern square_size, board_offset_x, board_offset_y
extern light_col, dark_col, highlight_col
extern assets_path
extern piece_name_ptrs
extern key_square_size, default_square_size
extern key_light_square, default_light_square
extern key_dark_square, default_dark_square
extern key_highlight, default_highlight
extern key_assets, default_assets
extern gfx_highlight_sq

extern SDL_Init, SDL_Quit
extern SDL_CreateWindow, SDL_DestroyWindow, SDL_GetWindowSurface
extern SDL_UpdateWindowSurface
extern SDL_RWFromFile, SDL_LoadBMP_RW, SDL_FreeSurface, SDL_SetColorKey
extern SDL_MapRGB, SDL_FillRect, SDL_UpperBlit
extern SDL_WaitEvent, SDL_WaitEventTimeout, SDL_Delay

; SDL constants
SDL_INIT_VIDEO         equ 0x00000020
SDL_WINDOW_SHOWN       equ 0x00000004
SDL_WINDOWPOS_CENTERED equ 0x2FFF0000

SDL_QUIT               equ 0x100
SDL_KEYDOWN            equ 0x300
SDL_MOUSEBUTTONDOWN    equ 0x401

SDL_BUTTON_LEFT        equ 1
SDL_PRESSED            equ 1

SDLK_ESCAPE            equ 0x1B
SDLK_q                 equ 0x71

; Makro pre volania SDL s 16-bajtovym zarovnanim zasobnika
; Pouziva r15 na ulozenie korekcie, lebo r11 je caller-saved
; a SDL funkcie ho mozu prepisat.
%macro sdl_call 1
    push r15
    mov r15, rsp
    and r15, 8
    sub rsp, r15
    call %1
    add rsp, r15
    pop r15
%endmacro

; ============================================================
; print_msg
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
; str_append
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
; parse_int_ptr
; ============================================================
parse_int_ptr:
    mov rsi, rdi
    jmp parse_int

; ============================================================
; parse_color_sdl - prevedie "0xRRGGBB" na 0x00RRGGBB
; ============================================================
parse_color_sdl:
    push rbx
    push rcx
    mov rsi, rdi

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
    jz .done
    cmp bl, '0'
    jl .done
    cmp bl, '9'
    jle .digit
    cmp bl, 'a'
    jl .maybe_upper
    cmp bl, 'f'
    jle .lower
    cmp bl, 'A'
    jl .done
    cmp bl, 'F'
    jle .upper
    jmp .done
.maybe_upper:
    cmp bl, 'A'
    jl .done
    cmp bl, 'F'
    jle .upper
    jmp .done
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
.done:
    pop rcx
    pop rbx
    ret

; ============================================================
; sdl_map_color - prevedie BGRA farbu na SDL pixel
; Vstup: eax = BGRA farba, rdi = SDL_PixelFormat pointer
; Vystup: eax = SDL farba
; ============================================================
sdl_map_color:
    push rdi
    push rsi
    push rdx
    push rcx
    sub rsp, 8
    ; red
    mov esi, eax
    shr esi, 16
    and esi, 0xFF
    ; green
    mov edx, eax
    shr edx, 8
    and edx, 0xFF
    ; blue
    mov ecx, eax
    and ecx, 0xFF
    sdl_call SDL_MapRGB
    add rsp, 8
    pop rcx
    pop rdx
    pop rsi
    pop rdi
    ret

; ============================================================
; sdl_set_colorkey - nastavi magenta ako transparentnu
; Vstup: rdi = surface
; ============================================================
sdl_set_colorkey:
    push rsi
    push rdx
    push rdi
    sub rsp, 8
    mov rdi, [rdi + 8]   ; surface->format
    mov rsi, 255
    mov rdx, 0
    mov rcx, 255
    sdl_call SDL_MapRGB
    mov rdi, [rsp + 8]   ; restore surface pointer
    mov rsi, 1
    mov rdx, rax
    sdl_call SDL_SetColorKey
    add rsp, 8
    pop rdi
    pop rdx
    pop rsi
    ret

; ============================================================
; load_bmp_sdl - nacita figurku do SDL_Surface
; Vstup: r12 = index 0..11
; ============================================================
load_bmp_sdl:
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
    lea rsi, [mode_rb]
    sdl_call SDL_RWFromFile
    test rax, rax
    jz .error
    mov rdi, rax
    mov rsi, 1
    sdl_call SDL_LoadBMP_RW
    test rax, rax
    jz .error
    mov r15, rax

    mov rdi, r15
    call sdl_set_colorkey

    lea rdi, [sdl_bmps]
    mov [rdi + r12*8], r15

    add rsp, 128
    xor rax, rax
    jmp .done

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
; load_all_bmps_sdl
; ============================================================
load_all_bmps_sdl:
    push r12
    xor r12, r12
.loop:
    cmp r12, 12
    jge .done
    call load_bmp_sdl
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
; sdl_init_colors
; ============================================================
sdl_init_colors:
    push rdi
    push rax
    mov rdi, [sdl_surface]
    mov rdi, [rdi + 8]       ; format

    mov eax, [light_col]
    call sdl_map_color
    mov [sdl_light], eax

    mov eax, [dark_col]
    call sdl_map_color
    mov [sdl_dark], eax

    mov eax, [highlight_col]
    call sdl_map_color
    mov [sdl_highlight], eax

    pop rax
    pop rdi
    ret

; ============================================================
; sdl_gfx_init
; ============================================================
sdl_gfx_init:
    push rbx
    push r12

    mov byte [gfx_highlight_sq], 255

    ; assets path
    lea rdi, [key_assets]
    lea rsi, [default_assets]
    call config_get
    lea rdi, [assets_path]
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

    ; colors (raw 24-bit for SDL)
    lea rdi, [key_light_square]
    lea rsi, [default_light_square]
    call config_get
    mov rdi, rax
    call parse_color_sdl
    mov [light_col], eax

    lea rdi, [key_dark_square]
    lea rsi, [default_dark_square]
    call config_get
    mov rdi, rax
    call parse_color_sdl
    mov [dark_col], eax

    lea rdi, [key_highlight]
    lea rsi, [default_highlight]
    call config_get
    mov rdi, rax
    call parse_color_sdl
    mov [highlight_col], eax

    ; board offset = 0 (board fills window)
    mov dword [board_offset_x], 0
    mov dword [board_offset_y], 0

    ; init SDL
    mov rdi, SDL_INIT_VIDEO
    sdl_call SDL_Init
    cmp rax, 0
    jl .sdl_error

    ; create window
    mov rdi, window_title
    mov rsi, SDL_WINDOWPOS_CENTERED
    mov rdx, SDL_WINDOWPOS_CENTERED
    mov eax, [square_size]
    shl eax, 3
    mov r12d, eax
    mov rcx, r12
    mov r8, r12
    mov r9, SDL_WINDOW_SHOWN
    sdl_call SDL_CreateWindow
    test rax, rax
    jz .window_error
    mov [sdl_window], rax

    mov rdi, rax
    sdl_call SDL_GetWindowSurface
    test rax, rax
    jz .window_error
    mov [sdl_surface], rax

    call sdl_init_colors

    call load_all_bmps_sdl
    test rax, rax
    jnz .bmp_error

    xor rax, rax
    jmp .done

.sdl_error:
    mov rdi, msg_sdl_error
    mov rsi, msg_sdl_error_len
    call print_msg
    sdl_call SDL_Quit
    mov rax, 1
    jmp .done

.window_error:
    mov rdi, msg_sdl_window
    mov rsi, msg_sdl_window_len
    call print_msg
    call sdl_gfx_close
    mov rax, 1
    jmp .done

.bmp_error:
    mov rdi, msg_sdl_bmp
    mov rsi, msg_sdl_bmp_len
    call print_msg
    call sdl_gfx_close
    mov rax, 1

.done:
    pop r12
    pop rbx
    ret

; ============================================================
; sdl_gfx_close
; ============================================================
sdl_gfx_close:
    push rax
    push rbx
    push r12

    xor r12, r12
.bmp_loop:
    cmp r12, 12
    jge .destroy
    lea rbx, [sdl_bmps]
    mov rax, [rbx + r12*8]
    test rax, rax
    jz .next_bmp
    mov rdi, rax
    sdl_call SDL_FreeSurface
    mov qword [rbx + r12*8], 0
.next_bmp:
    inc r12
    jmp .bmp_loop

.destroy:
    mov rax, [sdl_window]
    test rax, rax
    jz .quit
    mov rdi, rax
    sdl_call SDL_DestroyWindow
    mov qword [sdl_window], 0

.quit:
    sdl_call SDL_Quit

    pop r12
    pop rbx
    pop rax
    ret

; ============================================================
; screen_to_board
; Vstup: r12 = row, r13 = col
; Vystup: eax = square
; ============================================================
screen_to_board:
    cmp byte [board_flip], 0
    je .white_view
    mov eax, r12d
    shl eax, 3
    mov ecx, 7
    sub ecx, r13d
    add eax, ecx
    ret
.white_view:
    mov ecx, 7
    sub ecx, r12d
    shl ecx, 3
    add ecx, r13d
    mov eax, ecx
    ret

; ============================================================
; draw_square - vyplni jedno policko
; Vstup: r12=x, r13=y, r14=size, ebx=farba, rdi=surface
; ============================================================
draw_square:
    push rax
    push rcx
    push rdx
    push rsi
    sub rsp, 16

    mov dword [rsp], r12d      ; x
    mov dword [rsp+4], r13d    ; y
    mov dword [rsp+8], r14d    ; w
    mov dword [rsp+12], r14d   ; h

    mov rsi, rsp
    mov rdx, rbx
    sdl_call SDL_FillRect

    add rsp, 16
    pop rsi
    pop rdx
    pop rcx
    pop rax
    ret

; ============================================================
; draw_piece_sdl - blitne figurku na policko
; Vstup: r12=x, r13=y, r14=size, r15=bmp_index, rdi=surface
; ============================================================
draw_piece_sdl:
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push r8
    push r9
    push r14
    sub rsp, 32

    lea rax, [sdl_bmps]
    mov rsi, [rax + r15*8]
    test rsi, rsi
    jz .done

    ; get bmp w/h
    mov eax, [rsi + 16]
    mov r8d, eax
    mov eax, [rsi + 20]
    mov r9d, eax

    ; center in square
    mov ebx, r14d
    sub ebx, r8d
    shr ebx, 1
    add ebx, r12d
    mov ecx, r14d
    sub ecx, r9d
    shr ecx, 1
    add ecx, r13d

    mov dword [rsp], ebx       ; dest x
    mov dword [rsp+4], ecx     ; dest y
    mov dword [rsp+8], 0       ; w (ignored if NULL)
    mov dword [rsp+12], 0      ; h

    mov rcx, rsp               ; dstrect
    xor rsi, rsi               ; srcrect = NULL
    mov rdx, rdi               ; dst surface
    lea rax, [sdl_bmps]
    mov rdi, [rax + r15*8]     ; src surface
    sdl_call SDL_UpperBlit

.done:
    add rsp, 32
    pop r14
    pop r9
    pop r8
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
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

    mov r15, [sdl_surface]   ; dst surface
    mov r14d, [square_size]  ; square size

    xor r12, r12            ; row
.rank_loop:
    cmp r12, 8
    jge .refresh

    xor r13, r13            ; col
.file_loop:
    cmp r13, 8
    jge .next_rank

    push r12
    push r13
    ; compute board square
    call screen_to_board
    mov r11d, eax

    ; square color
    mov eax, r12d
    add eax, r13d
    test al, 1
    jz .light
    mov ebx, [sdl_dark]
    jmp .color_ok
.light:
    mov ebx, [sdl_light]
.color_ok:
    cmp r11b, [gfx_highlight_sq]
    jne .no_highlight
    mov ebx, [sdl_highlight]
.no_highlight:

    ; x = col * size, y = row * size
    mov eax, r14d
    mul r13d
    mov r8d, eax
    mov eax, r14d
    mul r12d
    mov r9d, eax

    mov rdi, r15
    mov r12d, r8d
    mov r13d, r9d
    push r11
    call draw_square
    pop r11

    ; piece
    movzx ecx, byte [board + r11]
    test ecx, ecx
    jz .draw_done

    mov edx, ecx
    and edx, COLOR_MASK
    shr edx, 3
    and ecx, PIECE_MASK
    dec ecx
    mov eax, edx
    imul eax, 6
    add eax, ecx          ; bmp index

    mov rdi, r15          ; surface (r12/r13 uz maju x/y z draw_square)
    push r15              ; uloz surface pointer
    mov r15d, eax         ; bmp index
    call draw_piece_sdl
    pop r15               ; obnov surface pointer

.draw_done:
    pop r13
    pop r12
    inc r13
    jmp .file_loop

.next_rank:
    inc r12
    jmp .rank_loop

.refresh:
    mov rdi, [sdl_window]
    sdl_call SDL_UpdateWindowSurface

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
; sdl_gfx_refresh
; ============================================================
sdl_gfx_refresh:
    push rax
    call gfx_draw_board
    pop rax
    ret

; ============================================================
; sdl_square_from_xy
; Vstup: r12=x, r13=y
; Vystup: eax=0..63 alebo -1
; ============================================================
sdl_square_from_xy:
    push r14
    push r15

    mov eax, r12d
    cmp eax, 0
    jl .invalid
    mov ecx, [square_size]
    xor edx, edx
    div ecx
    cmp eax, 8
    jge .invalid
    mov r14d, eax

    mov eax, r13d
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
; sdl_get_click
; Vystup: eax=x, ebx=y, -1 ak navrat
; ============================================================
sdl_get_click:
    push r12
    push r13
    push r14
    sub rsp, 128

.loop:
    ; skontroluj stdin bez blokovania (umozni zadat e2e4 pocas gfx)
    mov dword [rsp + 96], 0
    mov word [rsp + 100], 1
    mov word [rsp + 102], 0
    mov rax, 7
    lea rdi, [rsp + 96]
    mov rsi, 1
    xor rdx, rdx
    syscall
    cmp rax, 0
    jle .wait_event
    movzx rax, word [rsp + 102]
    test al, 1
    jz .wait_event

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

    cmp qword [move_buf_len], 1
    jne .check_len4
    cmp byte [move_buf], 'q'
    je .return
    jmp .wait_event

.check_len4:
    cmp qword [move_buf_len], 4
    jne .wait_event

    cmp byte [move_buf], 't'
    jne .check_exit
    cmp byte [move_buf + 1], 'e'
    jne .typed_move
    cmp byte [move_buf + 2], 'x'
    jne .typed_move
    cmp byte [move_buf + 3], 't'
    je .return
    jmp .typed_move

.check_exit:
    cmp byte [move_buf], 'e'
    jne .check_quit
    cmp byte [move_buf + 1], 'x'
    jne .typed_move
    cmp byte [move_buf + 2], 'i'
    jne .typed_move
    cmp byte [move_buf + 3], 't'
    je .return
    jmp .typed_move

.check_quit:
    cmp byte [move_buf], 'q'
    jne .typed_move
    cmp byte [move_buf + 1], 'u'
    jne .typed_move
    cmp byte [move_buf + 2], 'i'
    jne .typed_move
    cmp byte [move_buf + 3], 't'
    je .return

.typed_move:
    mov rax, -2
    mov rbx, -2
    jmp .done

.wait_event:
    mov rdi, rsp
    mov rsi, 50
    sdl_call SDL_WaitEventTimeout
    cmp rax, 0
    jle .loop

    mov eax, [rsp]
    cmp eax, SDL_QUIT
    je .return
    cmp eax, SDL_KEYDOWN
    je .key
    cmp eax, SDL_MOUSEBUTTONDOWN
    jne .loop

    ; mouse button
    cmp byte [rsp + 16], SDL_BUTTON_LEFT
    jne .loop
    cmp byte [rsp + 17], SDL_PRESSED
    jne .loop

    mov eax, [rsp + 20]
    mov ebx, [rsp + 24]

    cmp byte [debug], 0
    jz .no_click_log
    push rax
    push rbx
    push rsi
    push rdi
    mov rdi, msg_dbg_click_x
    mov rsi, msg_dbg_click_x_len
    mov rdx, rax
    call sdl_debug_num
    mov rdi, msg_dbg_click_y
    mov rsi, msg_dbg_click_y_len
    mov rdx, rbx
    call sdl_debug_num
    call print_newline
    pop rdi
    pop rsi
    pop rbx
    pop rax
.no_click_log:

    jmp .done

.key:
    mov eax, [rsp + 20]   ; keysym.sym
    cmp eax, SDLK_ESCAPE
    je .return
    cmp eax, SDLK_q
    je .return
    jmp .loop

.return:
    mov rax, -1
    mov rbx, -1

.done:
    add rsp, 128
    pop r14
    pop r13
    pop r12
    ret

; ============================================================
; sdl_debug_num - vypise spravu a cislo (rdi=msg, rsi=len, rdx=cislo)
; ============================================================
sdl_debug_num:
    push rax
    push rdx
    call print_msg
    pop rax
    call print_number
    call print_newline
    pop rax
    ret

; ============================================================
; sdl_human_turn
; Vystup: ax = tah, 0 ak navrat
; ============================================================
sdl_human_turn:
    push rbx
    push r12
    push r13
    push r14

.wait_source:
    mov byte [gfx_highlight_sq], 255
.first_click:
    call sdl_get_click
    cmp rax, -1
    je .text_return
    cmp rax, -2
    je .typed_move
    mov r12, rax
    mov r13, rbx
    call sdl_square_from_xy
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

    cmp byte [debug], 0
    jz .no_src_log
    mov rdi, msg_dbg_src
    mov rsi, msg_dbg_src_len
    mov rdx, r14
    call sdl_debug_num
.no_src_log:
    mov [gfx_highlight_sq], r14b
    call sdl_gfx_refresh

.second_click:
    call sdl_get_click
    cmp rax, -1
    je .text_return
    cmp rax, -2
    je .typed_move
    mov r12, rax
    mov r13, rbx
    call sdl_square_from_xy
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
    call sdl_gfx_refresh
    jmp .second_click

.second_target_ok:

    cmp byte [debug], 0
    jz .no_dst_log
    mov rdi, msg_dbg_dst
    mov rsi, msg_dbg_dst_len
    mov rdx, r15
    call sdl_debug_num
.no_dst_log:

    mov byte [gfx_highlight_sq], 255
    call sdl_gfx_refresh

    ; build move
    mov eax, r14d
    mov ecx, r15d
    shl ecx, 6
    or eax, ecx
    push rax

    cmp byte [debug], 0
    jz .no_move_log
    push rax
    mov rdi, msg_dbg_move
    mov rsi, msg_dbg_move_len
    mov rdx, r14
    call sdl_debug_num
    mov rdi, msg_dbg_to
    mov rsi, msg_dbg_to_len
    mov rdx, r15
    call sdl_debug_num
    pop rax
.no_move_log:

    call generate_all_moves
    pop rax
    call find_move
    cmp byte [debug], 0
    jz .no_found_log
    push rax
    mov rdi, msg_dbg_found
    mov rsi, msg_dbg_found_len
    mov rdx, rax
    call sdl_debug_num
    pop rax
.no_found_log:
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
    call sdl_gfx_refresh
    jmp .done

.illegal:
    cmp byte [debug], 0
    jz .no_illegal_log
    mov rdi, msg_dbg_illegal
    mov rsi, msg_dbg_illegal_len
    call print_msg
.no_illegal_log:
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
; sdl_engine_turn
; ============================================================
sdl_engine_turn:
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
    call sdl_gfx_refresh

    pop rax
    ret

; ============================================================
; sdl_gfx_run
; ============================================================
sdl_gfx_run:
    push rax

    mov rdi, msg_sdl_prompt
    mov rsi, msg_sdl_prompt_len
    call print_msg

.loop:
    call sdl_gfx_refresh

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

    call sdl_human_turn
    test ax, ax
    jz .done
    call apply_move
    call update_position_state
    call compute_hash
    call record_hash
    jmp .loop

.engine:
    call sdl_engine_turn
    jmp .loop

.done:
    call sdl_gfx_close
    mov rdi, msg_sdl_return
    mov rsi, msg_sdl_return_len
    call print_msg

    pop rax
    ret