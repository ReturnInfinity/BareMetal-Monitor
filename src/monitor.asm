BITS 64
ORG 0x001E0000

%include 'api/libBareMetal.asm'


start:
	; Grab video values from Pure64
	mov rsi, 0x5080
	xor eax, eax
	lodsd				; VIDEO_BASE
	mov [VideoBase], rax

	xor eax, eax
	xor ecx, ecx
	lodsw				; VIDEO_X
	mov [VideoX], ax		; ex: 1024
	xor edx, edx
	mov cl, [font_width]
	div cx
	mov [Screen_Cols], ax

	lodsw				; VIDEO_Y
	mov [VideoY], ax		; ex: 768
	xor edx, edx
	mov cl, [font_height]
	div cx
	mov [Screen_Rows], ax

	lodsb				; VIDEO_DEPTH
	mov [VideoDepth], al

	xor eax, eax
	xor ecx, ecx
	mov ax, [VideoX]
	mov cx, [VideoY]
	mul ecx
	mov [Screen_Pixels], eax
	xor ecx, ecx
	mov cl, [VideoDepth]
	shr cl, 3
	mul ecx
	mov [Screen_Bytes], eax

	xor eax, eax
	xor ecx, ecx
	mov ax, [VideoX]
	mov cl, [font_height]
	mul cx
	mov cl, [VideoDepth]
	shr cl, 3
	mul ecx
	mov dword [Screen_Row_2], eax

	mov eax, 0x00FFFFFF
	mov [FG_Color], eax
	mov eax, 0x00404040
	mov [BG_Color], eax

	call screen_clear
	mov ax, [Screen_Rows]
	dec ax
	mov [Screen_Cursor_Row], ax

poll:
	mov rsi, prompt
	call output
	mov rdi, temp_string
	mov rcx, 100
	call input
	jmp poll

	jmp $			; Spin forever

prompt: db '> ', 0
VideoBase: dq 0
Screen_Pixels: dd 0
Screen_Bytes: dd 0
Screen_Row_2: dd 0
FG_Color: dd 0
BG_Color: dd 0
VideoX: dw 0
VideoY: dw 0
Screen_Rows: dw 0
Screen_Cols: dw 0
Screen_Cursor_Row: dw 0
Screen_Cursor_Col: dw 0
VideoDepth: db 0


; -----------------------------------------------------------------------------
; input -- Take string from keyboard entry
;  IN:	RDI = location where string will be stored
;	RCX = maximum number of characters to accept
; OUT:	RCX = length of string that was received (NULL not counted)
;	All other registers preserved
input:
	push rdi
	push rdx			; Counter to keep track of max accepted characters
	push rax

	mov rdx, rcx			; Max chars to accept
	xor ecx, ecx			; Offset from start

input_more:
	mov al, '_'
	call output_char
	call dec_cursor
	call [b_input]
	jnc input_halt		; No key entered... halt until an interrupt is received
	cmp al, 0x1C			; If Enter key pressed, finish
	je input_done
	cmp al, 0x0E			; Backspace
	je input_backspace
	cmp al, 32			; In ASCII range (32 - 126)?
	jl input_more
	cmp al, 126
	jg input_more
	cmp rcx, rdx			; Check if we have reached the max number of chars
	je input_more		; Jump if we have (should beep as well)
	stosb				; Store AL at RDI and increment RDI by 1
	inc rcx				; Increment the counter
	call output_char		; Display char
	jmp input_more

input_backspace:
	test rcx, rcx			; backspace at the beginning? get a new char
	jz input_more
	mov al, ' '			; 0x20 is the character for a space
	call output_char		; Write over the last typed character with the space
	call dec_cursor		; Decrement the cursor again
	call dec_cursor		; Decrement the cursor
	dec rdi				; go back one in the string
	mov byte [rdi], 0x00		; NULL out the char
	dec rcx				; decrement the counter by one
	jmp input_more

input_halt:
	hlt				; Halt until another keystroke is received
	jmp input_more

input_done:
	xor al, al
	stosb				; We NULL terminate the string
	mov al, ' '
	call output_char
	call print_newline

	pop rax
	pop rdx
	pop rdi
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; inc_cursor -- Increment the cursor by one, scroll if needed
;  IN:	Nothing
; OUT:	All registers preserved
inc_cursor:
	push rax

	inc word [Screen_Cursor_Col]
	mov ax, [Screen_Cursor_Col]
	cmp ax, [Screen_Cols]
	jne inc_cursor_done
	mov word [Screen_Cursor_Col], 0
	inc word [Screen_Cursor_Row]
	mov ax, [Screen_Cursor_Row]
	cmp ax, [Screen_Rows]
	jne inc_cursor_done
	call screen_scroll
	dec word [Screen_Cursor_Row]

inc_cursor_done:
	pop rax
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; dec_cursor -- Decrement the cursor by one
;  IN:	Nothing
; OUT:	All registers preserved
dec_cursor:
	push rax

	cmp word [Screen_Cursor_Col], 0
	jne dec_cursor_done
	dec word [Screen_Cursor_Row]
	mov ax, [Screen_Cols]
	mov word [Screen_Cursor_Col], ax

dec_cursor_done:
	dec word [Screen_Cursor_Col]

	pop rax
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; print_newline -- Reset cursor to start of next line and scroll if needed
;  IN:	Nothing
; OUT:	All registers preserved
print_newline:
	push rax

	mov word [Screen_Cursor_Col], 0	; Reset column to 0
	mov ax, [Screen_Rows]		; Grab max rows on screen
	dec ax					; and subtract 1
	cmp ax, [Screen_Cursor_Row]		; Is the cursor already on the bottom row?
	je print_newline_scroll		; If so, then scroll
	inc word [Screen_Cursor_Row]		; If not, increment the cursor to next row
	jmp print_newline_done

print_newline_scroll:
	call screen_scroll

print_newline_done:
	pop rax
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; output -- Displays text
;  IN:	RSI = message location (zero-terminated string)
; OUT:	All registers preserved
output:
	push rcx

	call string_length
	call output_chars

	pop rcx
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; output_char -- Displays a char
;  IN:	AL  = char to display
; OUT:	All registers preserved
output_char:
	push rdi
	push rdx
	push rcx
	push rbx
	push rax

	call glyph
	call inc_cursor

	pop rax
	pop rbx
	pop rcx
	pop rdx
	pop rdi
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; pixel -- Put a pixel on the screen
;  IN:	EBX = Packed X & Y coordinates (YYYYXXXX)
;	EAX = Pixel Details (AARRGGBB)
; OUT:	All registers preserved
pixel:
	push rdi
	push rdx
	push rcx
	push rbx
	push rax

	push rax			; Save the pixel details
	mov rax, rbx
	shr eax, 16			; Isolate Y co-ordinate
	xor ecx, ecx
	mov cx, [VideoX]
	mul ecx				; Multiply Y by VideoX
	and ebx, 0x0000FFFF		; Isolate X co-ordinate
	add eax, ebx			; Add X
	mov rdi, [VideoBase]

	cmp byte [VideoDepth], 32
	je pixel_32

pixel_24:
	mov ecx, 3
	mul ecx				; Multiply by 3 as each pixel is 3 bytes
	add rdi, rax			; Add offset to pixel video memory
	pop rax				; Restore pixel details
	stosb
	shr eax, 8
	stosb
	shr eax, 8
	stosb
	jmp pixel_done

pixel_32:
	shl eax, 2			; Quickly multiply by 4
	add rdi, rax			; Add offset to pixel video memory
	pop rax				; Restore pixel details
	stosd

pixel_done:
	pop rax
	pop rbx
	pop rcx
	pop rdx
	pop rdi
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; glyph_put -- Put a glyph on the screen at the cursor location
;  IN:	AL  = char to display
; OUT:	All registers preserved
glyph:
	push rdi
	push rsi
	push rdx
	push rcx
	push rbx
	push rax

	and eax, 0x000000FF
	sub rax, 0x20
	mov ecx, 12			; Font height
	mul ecx
	mov rsi, font_data
	add rsi, rax			; add offset to correct glyph

; Calculate pixel co-ordinates for character
	xor ebx, ebx
	xor edx, edx
	xor eax, eax
	mov ax, [Screen_Cursor_Row]
	mov cx, 12			; Font height
	mul cx
	mov bx, ax
	shl ebx, 16
	xor edx, edx
	xor eax, eax
	mov ax, [Screen_Cursor_Col]
	mov cx, 6			; Font width
	mul cx
	mov bx, ax

	xor eax, eax
	xor ecx, ecx			; x counter
	xor edx, edx			; y counter

glyph_nextline:
	lodsb				; Load a line

glyph_nextpixel:
	cmp ecx, 6			; Font width
	je glyph_bailout		; Glyph row complete
	rol al, 1
	bt ax, 0
	jc glyph_pixel
	push rax
	mov eax, [BG_Color]
	call pixel
	pop rax
	jmp glyph_skip

glyph_pixel:
	push rax
	mov eax, [FG_Color]
	call pixel
	pop rax

glyph_skip:
	inc ebx
	inc ecx
	jmp glyph_nextpixel

glyph_bailout:
	xor ecx, ecx
	sub ebx, 6			; column start
	add ebx, 0x00010000		; next row
	inc edx
	cmp edx, 12			; Font height
	jne glyph_nextline

glyph_done:
	pop rax
	pop rbx
	pop rcx
	pop rdx
	pop rsi
	pop rdi
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; output_chars -- Displays text
;  IN:	RSI = message location (an ASCII string, not zero-terminated)
;	RCX = number of chars to print
; OUT:	All registers preserved
output_chars:
	push rdi
	push rsi
	push rcx
	push rax
	pushfq

	cld				; Clear the direction flag.. we want to increment through the string

output_chars_nextchar:
	jrcxz output_chars_done
	dec rcx
	lodsb				; Get char from string and store in AL
	cmp al, 13			; Check if there was a newline character in the string
	je output_chars_newline		; If so then we print a new line
	cmp al, 10			; Check if there was a newline character in the string
	je output_chars_newline		; If so then we print a new line
	cmp al, 9
	je output_chars_tab
	call output_char
	jmp output_chars_nextchar

output_chars_newline:
	mov al, [rsi]
	cmp al, 10
	je output_chars_newline_skip_LF
	call print_newline
	jmp output_chars_nextchar

output_chars_newline_skip_LF:
	test rcx, rcx
	jz output_chars_newline_skip_LF_nosub
	dec rcx

output_chars_newline_skip_LF_nosub:
	inc rsi
	call print_newline
	jmp output_chars_nextchar

output_chars_tab:
	push rcx
	mov ax, [Screen_Cursor_Col]	; Grab the current cursor X value (ex 7)
	mov cx, ax
	add ax, 8			; Add 8 (ex 15)
	shr ax, 3			; Clear lowest 3 bits (ex 8)
	shl ax, 3			; Bug? 'xor al, 7' doesn't work...
	sub ax, cx			; (ex 8 - 7 = 1)
	mov cx, ax
	mov al, ' '

output_chars_tab_next:
	call output_char
	dec cx
	jnz output_chars_tab_next
	pop rcx
	jmp output_chars_nextchar

output_chars_done:
	popfq
	pop rax
	pop rcx
	pop rsi
	pop rdi
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; scroll_screen -- Scrolls the screen up by one line
;  IN:	Nothing
; OUT:	All registers preserved
screen_scroll:
	push rsi
	push rdi
	push rcx
	push rax
	pushfq

	cld				; Clear the direction flag as we want to increment through memory
	xor ecx, ecx
	xor esi, esi
	mov rdi, [VideoBase]
	mov esi, [Screen_Row_2]
	add rsi, rdi
	mov ecx, [Screen_Bytes]
	rep movsb

screen_scroll_done:
	popfq
	pop rax
	pop rcx
	pop rdi
	pop rsi
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; screen_clear -- Clear the screen
;  IN:	AL
; OUT:	All registers preserved
screen_clear:
	push rdi
	push rcx
	push rax
	pushfq

	cld				; Clear the direction flag as we want to increment through memory
	xor ecx, ecx
	mov rdi, [VideoBase]
	xor eax, eax
	mov al, [BG_Color]		; TODO - needs to use the whole value
	mov ecx, [Screen_Bytes]
	add ecx, 100000			; Fudge value for last line.. gross
	rep stosb

screen_clear_done:
	popfq
	pop rax
	pop rcx
	pop rdi
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; string_length -- Return length of a string
;  IN:	RSI = string location
; OUT:	RCX = length (not including the NULL terminator)
;	All other registers preserved
string_length:
	push rdi
	push rax

	xor ecx, ecx
	xor eax, eax
	mov rdi, rsi
	not rcx
	cld
	repne scasb			; compare byte at RDI to value in AL
	not rcx
	dec rcx

	pop rax
	pop rdi
	ret
; -----------------------------------------------------------------------------


%include 'font.inc'

temp_string: db 0

; =============================================================================
; EOF
