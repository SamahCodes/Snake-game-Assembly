; Snake Game for EMU8086
; Same structure, rebuilt: fixed buffer shift and safe delay
; Use arrow keys to control snake
; Eat 'X' to grow and increase score

org 100h

jmp start

; ----------------
; Constants
; ----------------
VID_SEG     equ 0B800h
SCREEN_COLS equ 80
SCREEN_ROWS equ 25

WALL_ATTR   equ 07h
SNAKE_ATTR  equ 0Ah
FOOD_ATTR   equ 0Ch
TEXT_ATTR   equ 07h

WALL_CHAR   equ '#'
SNAKE_CHAR  equ 'O'
FOOD_CHAR   equ 'X'
SPACE_CHAR  equ ' '

MAX_LEN     equ 150

; ----------------
; Variables
; ----------------
snake_len   db 3
score       dw 0

head_row    db 12
head_col    db 40

food_row    db 8
food_col    db 30

dir         db 0          ; 0=right, 1=left, 2=down, 3=up

speed_delay dw 2000

temp_tail_row db 0
temp_tail_col db 0

snake_buf   db MAX_LEN*2 dup (0)

msg_gameover db 13,10,'*** GAME OVER ***$'
final_label  db 13,10,'Final Score: $'
score_label  db 'SCORE: $'

numbuf db 6 dup(0)

; ----------------
; Main Program
; ----------------
start:
    mov ax, cs
    mov ds, ax
    
    ; set video mode to text mode 80x25 (just to be sure)
    mov ah, 0
    mov al, 3
    int 10h
    
    mov ax, VID_SEG
    mov es, ax
    
    call init_snake_buffer
    call clear_screen
    call draw_walls
    call draw_full_snake
    call place_food
    call draw_score

game_loop:
    call read_key_nonblock
    call move_snake
    call draw_score
    call delay
    jmp game_loop

; ============================
; init_snake_buffer
; ============================
init_snake_buffer:
    push ax
    push bx
    push cx
    push si
    
    mov cl, [snake_len]
    xor si, si
    mov al, [head_row]
    mov ah, [head_col]
    xor bl, bl

init_buf_loop:
    mov [snake_buf + si], al
    inc si
    mov dl, ah
    sub dl, bl
    mov [snake_buf + si], dl
    inc si
    inc bl
    dec cl
    jnz init_buf_loop
    
    pop si
    pop cx
    pop bx
    pop ax
    ret

; ============================
; draw_full_snake
; ============================
draw_full_snake:
    push ax
    push bx
    push cx
    push dx
    push si
    
    mov cl, [snake_len]
    xor ch, ch
    xor si, si
    cmp cx, 0
    je draw_snake_done

draw_snake_loop:
    mov dh, [snake_buf + si]
    mov dl, [snake_buf + si + 1]
    mov al, SNAKE_CHAR
    mov ah, SNAKE_ATTR
    call put_char_rc_attr
    add si, 2
    loop draw_snake_loop

draw_snake_done:
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ============================
; move_snake
; ============================
move_snake:
    push ax
    push bx
    push cx
    push dx
    push si
    
    ; compute new head position
    mov al, [dir]
    cmp al, 0
    je move_right
    cmp al, 1
    je move_left
    cmp al, 2
    je move_down
    jmp move_up

move_right:
    inc byte ptr [head_col]
    jmp check_collision
move_left:
    dec byte ptr [head_col]
    jmp check_collision
move_down:
    inc byte ptr [head_row]
    jmp check_collision
move_up:
    dec byte ptr [head_row]

check_collision:
    ; check wall collision (rows 0..24, but interior walls from 1..23 and 1..78 for cols)
    mov al, [head_row]
    cmp al, 1
    jb hit_wall_jump
    cmp al, 23
    ja hit_wall_jump
    mov al, [head_col]
    cmp al, 1
    jb hit_wall_jump
    cmp al, 78
    ja hit_wall_jump
    jmp save_tail

hit_wall_jump:
    jmp hit_wall

save_tail:
    ; save old tail position
    mov al, [snake_len]
    dec al
    xor ah, ah
    shl ax, 1
    mov si, ax
    mov al, [snake_buf + si]
    mov [temp_tail_row], al
    mov al, [snake_buf + si + 1]
    mov [temp_tail_col], al
    
    ; check if eating food
    mov al, [head_row]
    cmp al, [food_row]
    jne no_eat
    mov al, [head_col]
    cmp al, [food_col]
    jne no_eat
    
    ; eat food (simple beep)
    mov dl, 7
    mov ah, 02h
    int 21h
    
    inc word ptr [score]
    
    mov al, [snake_len]
    inc al
    cmp al, MAX_LEN
    jbe grow_ok
    mov al, MAX_LEN
grow_ok:
    mov [snake_len], al
    call place_food
    mov bl, 1
    jmp shift_buffer

no_eat:
    mov bl, 0

; ============================
; SHIFT BUFFER (corrected)
; ============================
shift_buffer:
    ; We'll move (snake_len - 1) pairs one step toward tail:
    ; number_of_moves = snake_len - 1
    ; if number_of_moves == 0 -> nothing to move (single head only)
    mov al, [snake_len]
    dec al               ; AL = moves (N-1)
    xor ah, ah
    mov cx, ax           ; CX = moves
    cmp cx, 0
    je shift_place_head

    ; compute SI = (moves - 1) * 2 -> source index of the first copy
    mov si, cx
    dec si               ; SI = moves - 1
    shl si, 1            ; SI = (moves-1) * 2

shift_loop_fixed:
    ; copy pair at [si] to [si+2]
    mov al, [snake_buf + si]        ; row
    mov ah, [snake_buf + si + 1]    ; col
    mov [snake_buf + si + 2], al
    mov [snake_buf + si + 3], ah

    sub si, 2
    dec cx
    jnz shift_loop_fixed

shift_place_head:
    ; place new head at index 0
    mov al, [head_row]
    mov [snake_buf], al
    mov al, [head_col]
    mov [snake_buf + 1], al

    ; draw new head
    mov dh, [head_row]
    mov dl, [head_col]
    mov al, SNAKE_CHAR
    mov ah, SNAKE_ATTR
    call put_char_rc_attr

    ; if we did NOT eat (bl == 0) erase the saved tail
    cmp bl, 1
    je skip_erase

    mov dh, [temp_tail_row]
    mov dl, [temp_tail_col]
    mov al, SPACE_CHAR
    mov ah, TEXT_ATTR
    call put_char_rc_attr

skip_erase:
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

hit_wall:
    call game_over
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ============================
; place_food
; ============================
place_food:
    push ax
    push bx
    push cx
    push dx
    
    mov ah, 0
    int 1Ah
    mov bx, dx
    
    ; calculate row (1..23)
    mov ax, bx
    xor dx, dx
    mov cx, 23
    div cx
    mov al, dl
    inc al
    mov [food_row], al
    
    ; calculate col (1..78)
    mov ax, bx
    xor dx, dx
    mov cx, 78
    div cx
    mov al, dl
    inc al
    mov [food_col], al
    
    ; draw food
    mov dh, [food_row]
    mov dl, [food_col]
    mov al, FOOD_CHAR
    mov ah, FOOD_ATTR
    call put_char_rc_attr
    
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ============================
; draw_score  (fixed)
; ============================
draw_score:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    
    ; draw label at row 0, starting column 1
    mov si, offset score_label
    mov cl, 1         ; column counter (low byte)
    mov dh, 0         ; row = 0

score_label_loop2:
    mov al, [si]
    cmp al, '$'
    je score_label_end2
    mov dl, cl
    mov ah, TEXT_ATTR
    call put_char_rc_attr
    inc si
    inc cl
    jmp score_label_loop2

score_label_end2:
    ; convert score to string into numbuf
    mov ax, [score]
    mov si, offset numbuf
    add si, 5
    mov byte ptr [si], 0
    dec si
    
    cmp ax, 0
    jne score_convert2
    mov byte ptr [si], '0'
    jmp score_print_start2

score_convert2:
    mov bx, 10
score_convert_loop2:
    xor dx, dx
    div bx
    add dl, '0'
    mov [si], dl
    dec si
    cmp ax, 0
    jne score_convert_loop2

score_print_start2:
    inc si
    ; print digits starting at current column CL
score_print_loop2:
    mov al, [si]
    cmp al, 0
    je score_end2
    mov dl, cl
    mov dh, 0
    mov ah, TEXT_ATTR
    call put_char_rc_attr
    inc si
    inc cl
    jmp score_print_loop2

score_end2:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ============================
; read_key_nonblock
; ============================
read_key_nonblock:
    push ax
    push bx
    
    mov ah, 01h
    int 16h
    jz key_done
    
    mov ah, 00h
    int 16h
    
    cmp al, 0
    jne key_done
    
    cmp ah, 72
    je key_up
    cmp ah, 80
    je key_down
    cmp ah, 75
    je key_left
    cmp ah, 77
    je key_right
    jmp key_done

key_up:
    cmp byte ptr [dir], 2
    je key_done
    mov byte ptr [dir], 3
    jmp key_done
key_down:
    cmp byte ptr [dir], 3
    je key_done
    mov byte ptr [dir], 2
    jmp key_done
key_left:
    cmp byte ptr [dir], 0
    je key_done
    mov byte ptr [dir], 1
    jmp key_done
key_right:
    cmp byte ptr [dir], 1
    je key_done
    mov byte ptr [dir], 0

key_done:
    pop bx
    pop ax
    ret

; ============================
; clear_screen
; ============================
clear_screen:
    push ax
    push cx
    push di
    push es
    
    mov ax, 0B800h
    mov es, ax
    xor di, di
    mov cx, SCREEN_COLS * SCREEN_ROWS
    mov al, SPACE_CHAR
    mov ah, TEXT_ATTR
    rep stosw
    
    pop es
    pop di
    pop cx
    pop ax
    ret

; ============================
; draw_walls
; ============================
draw_walls:
    push ax
    push bx
    push cx
    push dx
    
    ; top row
    mov dh, 0
    xor dl, dl
    mov cx, SCREEN_COLS
wall_top_loop:
    mov al, WALL_CHAR
    mov ah, WALL_ATTR
    call put_char_rc_attr
    inc dl
    loop wall_top_loop
    
    ; bottom row
    mov dh, SCREEN_ROWS - 1
    xor dl, dl
    mov cx, SCREEN_COLS
wall_bottom_loop:
    mov al, WALL_CHAR
    mov ah, WALL_ATTR
    call put_char_rc_attr
    inc dl
    loop wall_bottom_loop
    
    ; left and right walls
    mov cx, SCREEN_ROWS
    xor dh, dh
wall_side_loop:
    mov dl, 0
    mov al, WALL_CHAR
    mov ah, WALL_ATTR
    call put_char_rc_attr
    
    mov dl, SCREEN_COLS - 1
    mov al, WALL_CHAR
    mov ah, WALL_ATTR
    call put_char_rc_attr
    
    inc dh
    loop wall_side_loop
    
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ============================
; put_char_rc_attr
; DH = row, DL = col
; AL = char, AH = attribute
; ============================
put_char_rc_attr:
    push ax
    push bx
    push cx
    push dx
    push di
    push es
    
    ; save character and attribute
    mov bl, al
    mov bh, ah
    
    ; calculate offset: (row * 80 + col) * 2
    mov al, dh      ; AL = row
    mov cl, dl      ; CL = col (save it)
    xor ah, ah
    mov dx, 80
    mul dx          ; AX = row * 80
    mov dl, cl      ; DL = col
    xor dh, dh      ; DX = col
    add ax, dx      ; AX = row * 80 + col
    shl ax, 1       ; AX = (row * 80 + col) * 2
    mov di, ax
    
    ; set ES to video segment
    mov ax, 0B800h
    mov es, ax
    
    ; write character and attribute
    mov al, bl
    mov es:[di], al
    inc di
    mov al, bh
    mov es:[di], al
    
    pop es
    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ============================
; game_over
; ============================
game_over:
    push ax
    push cx
    push dx
    
    ; beep 3 times
    mov cx, 3
beep_loop:
    mov dl, 7
    mov ah, 02h
    int 21h
    call small_delay
    loop beep_loop
    
    ; print game over
    mov dx, offset msg_gameover
    mov ah, 09h
    int 21h
    
    ; print final score label
    mov dx, offset final_label
    mov ah, 09h
    int 21h
    
    ; convert score
    mov ax, [score]
    mov si, offset numbuf
    add si, 5
    mov byte ptr [si], '$'
    dec si
    
    cmp ax, 0
    jne gameover_convert
    mov byte ptr [si], '0'
    dec si
    jmp gameover_print

gameover_convert:
    mov bx, 10
gameover_convert_loop:
    xor dx, dx
    div bx
    add dl, '0'
    mov [si], dl
    dec si
    cmp ax, 0
    jne gameover_convert_loop

gameover_print:
    inc si
    mov dx, si
    mov ah, 09h
    int 21h
    
    ; wait for key
    mov ah, 00h
    int 16h
    
    ; exit
    mov ax, 4C00h
    int 21h
    
    pop dx
    pop cx
    pop ax
    ret

; ============================
; small_delay
; ============================
small_delay:
    push cx
    mov cx, 30000
small_delay_loop:
    nop
    loop small_delay_loop
    pop cx
    ret

; ============================
; delay -- BIOS-safe non-freezing delay
; ============================
delay:
    push ax
    push bx
    push cx
    push dx

    mov ah, 0      ; read timer ticks
    int 1Ah        ; CX:DX = tick count since midnight

    mov bx, dx     ; save starting tick

delay_wait:
    mov ah, 0
    int 1Ah        ; read new ticks
    sub dx, bx     ; elapsed = current - start
    cmp dx, 1    ; delay amount (adjustable)
    jb delay_wait  ; if (elapsed < 2 ticks) keep waiting

    pop dx
    pop cx
    pop bx
    pop ax
    ret

    

end start
