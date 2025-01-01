; =============================================================================
; BareMetal Monitor UI
; Copyright (C) 2008-2025 Return Infinity -- see LICENSE.TXT
;
; This file contains all of the functions needed for displaying a text UI in
; the graphics mode configured by the OS loader.
;
; ui_init needs to be called first as it gathers the relevant details for the
; screen and font.
; =============================================================================


BITS 64


; -----------------------------------------------------------------------------
; ui_init -- Initialize a graphical user interface
;  IN:	Nothing
; OUT:	Nothing
ui_init:
	push rdx
	push rcx
	push rax

	; Gather screen values from kernel
	mov rcx, SCREEN_LFB_GET		; 64-bit - Base address of LFB
	call [b_system]
	mov [VideoBase], rax
	mov [LastLine], rax		; Rolling line marker
	xor eax, eax
	mov rcx, SCREEN_X_GET		; 16-bit - X resolution
	call [b_system]
	mov [VideoX], ax
	mov rcx, SCREEN_Y_GET		; 16-bit - Y resolution
	call [b_system]
	mov [VideoY], ax
	mov rcx, SCREEN_PPSL_GET	; 16-bit - Pixels per scan line
	call [b_system]
	mov [VideoPPSL], eax

	; Calculate screen parameters
	xor eax, eax
	xor ecx, ecx
	mov ax, [VideoX]
	mov cx, [VideoY]
	mul ecx
	mov [Screen_Pixels], eax
	mov ecx, 4
	mul ecx
	mov [Screen_Bytes], eax

	call screen_clear

	; Calculate display parameters based on font dimensions
	xor eax, eax
	xor edx, edx
	xor ecx, ecx
	mov ax, [VideoX]
	mov cl, [font_width]
	div cx				; Divide VideoX by font_width
	mov [Screen_Cols], ax
	xor eax, eax
	xor edx, edx
	xor ecx, ecx
	mov ax, [VideoY]
	mov cl, [font_height]
	div cx				; Divide VideoY by font_height
	mov [Screen_Rows], ax

	; Overwrite the kernel b_output function so output goes to the screen instead of the serial port
	mov rax, output_chars
	mov [0x100018], rax

	; Set b_user call entry point
	mov rax, ui_api
	mov [0x100048], rax

	pop rax
	pop rcx
	pop rdx
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; ui_input -- Take string from keyboard entry
;  IN:	RDI = location where string will be stored
;	RCX = maximum number of characters to accept
; OUT:	RCX = length of string that was received (NULL not counted)
;	All other registers preserved
ui_input:
	push rdi
	push rdx			; Counter to keep track of max accepted characters
	push rax

	mov rdx, rcx			; Max chars to accept
	xor ecx, ecx			; Offset from start

ui_input_more:
	mov al, '_'			; Cursor character
	call output_char		; Output the cursor
	call dec_cursor			; Set the cursor back by 1
ui_input_halt:
	hlt				; Halt until an interrupt is received
	call [b_input]			; Returns the character entered. 0 if there was none
	jz ui_input_halt		; If there was no character then halt until an interrupt is received
ui_input_process:
	cmp al, 0x1C			; If Enter key pressed, finish
	je ui_input_done
	cmp al, 0x0E			; Backspace
	je ui_input_backspace
	cmp al, 32			; In ASCII range (32 - 126)?
	jl ui_input_more
	cmp al, 126
	jg ui_input_more
	cmp rcx, rdx			; Check if we have reached the max number of chars
	je ui_input_more		; Jump if we have (should beep as well)
	stosb				; Store AL at RDI and increment RDI by 1
	inc rcx				; Increment the counter
	call output_char		; Display char
	jmp ui_input_more

ui_input_backspace:
	test rcx, rcx			; backspace at the beginning? get a new char
	jz ui_input_more
	mov al, ' '			; 0x20 is the character for a space
	call output_char		; Write over the last typed character with the space
	call dec_cursor			; Decrement the cursor again
	call dec_cursor			; Decrement the cursor
	dec rdi				; go back one in the string
	mov byte [rdi], 0x00		; NULL out the char
	dec rcx				; decrement the counter by one
	jmp ui_input_more

ui_input_done:
	xor al, al
	stosb				; We NULL terminate the string
	mov al, ' '
	call output_char		; Overwrite the cursor

	pop rax
	pop rdx
	pop rdi
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; ui_output -- Displays text
;  IN:	RSI = message location (zero-terminated string)
; OUT:	All registers preserved
ui_output:
	push rcx

	call string_length		; Calculate the length of the provided string
	call output_chars		; Output the required number of characters

	pop rcx
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; inc_cursor -- Increment the cursor by one, scroll if needed
;  IN:	Nothing
; OUT:	All registers preserved
inc_cursor:
	push rax

	inc word [Screen_Cursor_Col]	; Increment the current cursor column
	mov ax, [Screen_Cursor_Col]
	cmp ax, [Screen_Cols]		; Compare it to the # of columns for the screen
	jne inc_cursor_done		; If not equal we are done
	mov word [Screen_Cursor_Col], 0	; Reset column to 0
	inc word [Screen_Cursor_Row]	; Increment the current cursor row
	mov ax, [Screen_Cursor_Row]
	cmp ax, [Screen_Rows]		; Compare it to the # of rows for the screen
	jne inc_cursor_done		; If not equal we are done
	mov word [Screen_Cursor_Row], 0
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

	cmp word [Screen_Cursor_Col], 0	; Compare the current cursor column to 0
	jne dec_cursor_done		; If not equal we are done
	dec word [Screen_Cursor_Row]	; Otherwise decrement the row
	mov ax, [Screen_Cols]		; Get the total colums and save it as the current
	mov word [Screen_Cursor_Col], ax

dec_cursor_done:
	dec word [Screen_Cursor_Col]	; Decrement the cursor as usual

	pop rax
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; output_chars -- Displays text
;  IN:	RSI = message location (an ASCII string, not zero-terminated)
;	RCX = number of chars to print
; OUT:	All registers preserved
output_chars:
	push rsi
	push rcx
	push rax

output_chars_nextchar:
	cmp rcx, 0
	jz output_chars_done
	dec rcx
	lodsb				; Get char from string and store in AL
	cmp al, 0x0A			; LF - Check if there was a newline (aka line feed) character in the string
	je output_chars_newline		; If so then we print a new line
	cmp al, 0x0D			; CR - Check if there was a carriage return character in the string
	je output_chars_cr		; If so reset to column 0
	cmp al, 9
	je output_chars_tab
	call output_char
	jmp output_chars_nextchar

output_chars_newline:
	mov al, [rsi]
	cmp al, 0x0A
	je output_chars_newline_skip_LF
	call output_newline
	jmp output_chars_nextchar

output_chars_cr:
	mov al, [rsi]			; Check the next character
	cmp al, 0x0A			; Is it a newline?
	je output_chars_newline		; If so, display a newline and ignore the carriage return
	push rcx
	xor eax, eax
	xor ecx, ecx
	mov [Screen_Cursor_Col], ax
	mov cx, [Screen_Cols]
	mov al, ' '
output_chars_cr_clearline:
	call output_char
	dec cx
	jnz output_chars_cr_clearline
	dec word [Screen_Cursor_Row]
	xor eax, eax
	mov [Screen_Cursor_Col], ax
	pop rcx
	jmp output_chars_nextchar

output_chars_newline_skip_LF:
	test rcx, rcx
	jz output_chars_newline_skip_LF_nosub
	dec rcx

output_chars_newline_skip_LF_nosub:
	inc rsi
	call output_newline
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
	pop rax
	pop rcx
	pop rsi
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; output_char -- Displays a char
;  IN:	AL  = char to display
; OUT:	All registers preserved
output_char:
	call glyph
	call inc_cursor
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; output_newline -- Reset cursor to start of next line and wrap if needed
;  IN:	Nothing
; OUT:	All registers preserved
output_newline:
	push rax

	mov word [Screen_Cursor_Col], 0	; Reset column to 0
	mov ax, [Screen_Rows]		; Grab max rows on screen
	dec ax				; and subtract 1
	cmp ax, [Screen_Cursor_Row]	; Is the cursor already on the bottom row?
	je output_newline_wrap		; If so, then wrap
	inc word [Screen_Cursor_Row]	; If not, increment the cursor to next row
	jmp output_newline_done

output_newline_wrap:
	mov word [Screen_Cursor_Row], 0

output_newline_done:
	call draw_line
	pop rax
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; glyph_put -- Put a glyph on the screen at the cursor location
;  IN:	AL  = char to display
; OUT:	All registers preserved
glyph:
	push rsi
	push rdx
	push rcx
	push rbx
	push rax

	and eax, 0x000000FF
	cmp al, 0x20
	jl hidden
	cmp al, 127
	jg hidden
	sub rax, 0x20
	jmp load_char
hidden:
	mov al, 0
load_char:

	mov ecx, font_h			; Font height
	mul ecx
	mov rsi, font_data
	add rsi, rax			; add offset to correct glyph

; Calculate pixel co-ordinates for character
	xor ebx, ebx
	xor edx, edx
	xor eax, eax
	mov ax, [Screen_Cursor_Row]
	mov cx, font_h			; Font height
	mul cx
	mov bx, ax
	shl ebx, 16
	xor edx, edx
	xor eax, eax
	mov ax, [Screen_Cursor_Col]
	mov cx, font_w			; Font width
	mul cx
	mov bx, ax

	xor eax, eax
	xor ecx, ecx			; x counter
	xor edx, edx			; y counter

glyph_nextline:
	lodsb				; Load a line

glyph_nextpixel:
	cmp ecx, font_w			; Font width
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
	sub ebx, font_w			; column start
	add ebx, 0x00010000		; next row
	inc edx
	cmp edx, font_h			; Font height
	jne glyph_nextline

glyph_done:
	pop rax
	pop rbx
	pop rcx
	pop rdx
	pop rsi
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

	; Calculate offset in video memory and store pixel
	push rax			; Save the pixel details
	mov rax, rbx
	shr eax, 16			; Isolate Y co-ordinate
	xor ecx, ecx
	mov cx, [VideoPPSL]
	mul ecx				; Multiply Y by VideoPPSL
	and ebx, 0x0000FFFF		; Isolate X co-ordinate
	add eax, ebx			; Add X
	mov rbx, rax			; Save the offset to RBX
	mov rdi, [VideoBase]		; Store the pixel to video memory
	pop rax				; Restore pixel details
	shl ebx, 2			; Quickly multiply by 4
	add rdi, rbx			; Add offset in video memory
	stosd				; Output pixel to video memory

	pop rax
	pop rbx
	pop rcx
	pop rdx
	pop rdi
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; screen_clear -- Clear the screen
;  IN:	Nothing
; OUT:	All registers preserved
screen_clear:
	push rdi
	push rcx
	push rax

	mov word [Screen_Cursor_Col], 0
	mov word [Screen_Cursor_Row], 0

	; Set the Frame Buffer to the background colour
	mov rdi, [VideoBase]
	mov eax, [BG_Color]
	mov ecx, [Screen_Bytes]
	shr ecx, 2			; Quick divide by 4
	rep stosd

	call draw_line

	pop rax
	pop rcx
	pop rdi
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; draw_line
draw_line:
	push rdi
	push rdx
	push rcx
	push rax

; Clear the previously drawn line
	mov rdi, [LastLine]
	mov cx, [VideoPPSL]
	mov eax, [BG_Color]
	rep stosd

; Display a line under the current cursor row
	mov rdi, [VideoBase]
	xor ecx, ecx
	xor eax, eax
	mov ax, [Screen_Cursor_Row]
	add ax, 1
	mov cx, font_h * 4		; Font height
	mul cx
	mov cx, [VideoPPSL]
	mul ecx				; Multiply Y by VideoPPSL
	add rdi, rax
	mov [LastLine], rdi
	xor ecx, ecx
	mov cx, [VideoPPSL]
	mov eax, [Line_Color]
	rep stosd

; Clear the next row of text
	mov ax, [Screen_Cursor_Row]	; Get the current cursor row
	inc ax				; Inc by 1 as it is 0-based
	cmp ax, [Screen_Rows]		; Compare it to the # of rows for the screen
	jne draw_line_skip
	mov rdi, [VideoBase]		; Roll RDI back to the start of video memory
draw_line_skip:
	xor eax, eax
	mov ax, [VideoPPSL]
	mov ecx, 12
	mul ecx
	mov ecx, eax
	mov eax, [BG_Color]
	rep stosd

	pop rax
	pop rcx
	pop rdx
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
	repne scasb			; compare byte at RDI to value in AL
	not rcx
	dec rcx

	pop rax
	pop rdi
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; ui_api -- API calls for the UI
;  IN:	RCX = API function
;	RAX = Value (depending on the function)
; OUT:	RAX = Value (depending on the function)
;	All other registers preserved
ui_api:
; Use CL register as an index to the function table
	and ecx, 0xFF			; Keep lower 8-bits only
; To save memory, the functions are placed in 16-bit frames
	lea ecx, [ui_api_table+ecx*2]	; extract function from table by index
	mov cx, [ecx]			; limit jump to 16-bit
	jmp rcx				; jump to function

ui_api_ret:
	ret

ui_api_get_fg:
	mov eax, [FG_Color]
	ret

ui_api_get_bg:
	mov eax, [BG_Color]
	ret

ui_api_get_cursor_row:
	xor eax, eax
	mov ax, [Screen_Cursor_Row]
	ret

ui_api_get_cursor_col:
	xor eax, eax
	mov ax, [Screen_Cursor_Col]
	ret

ui_api_get_cursor_row_max:
	xor eax, eax
	mov ax, [Screen_Rows]
	ret

ui_api_get_cursor_col_max:
	xor eax, eax
	mov ax, [Screen_Cols]
	ret

ui_api_set_fg:
	mov [FG_Color], eax
	ret

ui_api_set_bg:
	mov [BG_Color], eax
	ret

ui_api_set_cursor_row:
	mov [Screen_Cursor_Row], ax
	ret

ui_api_set_cursor_col:
	mov [Screen_Cursor_Col], ax
	ret

ui_api_set_cursor_row_max:
	mov [Screen_Rows], ax
	ret

ui_api_set_cursor_col_max:
	mov [Screen_Cols], ax
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; UI API index table
ui_api_table:
	dw ui_api_ret			; 0x00
	dw ui_api_get_fg		; 0x01
	dw ui_api_get_bg		; 0x02
	dw ui_api_get_cursor_row	; 0x03
	dw ui_api_get_cursor_col	; 0x04
	dw ui_api_get_cursor_row_max	; 0x05
	dw ui_api_get_cursor_col_max	; 0x06
	dw ui_api_ret			; 0x07
	dw ui_api_ret			; 0x08
	dw ui_api_ret			; 0x09
	dw ui_api_ret			; 0x0A
	dw ui_api_ret			; 0x0B
	dw ui_api_ret			; 0x0C
	dw ui_api_ret			; 0x0D
	dw ui_api_ret			; 0x0E
	dw ui_api_ret			; 0x0F
	dw ui_api_ret			; 0x10
	dw ui_api_set_fg		; 0x11
	dw ui_api_set_bg		; 0x12
	dw ui_api_set_cursor_row	; 0x13
	dw ui_api_set_cursor_col	; 0x14
	dw ui_api_set_cursor_row_max	; 0x15
	dw ui_api_set_cursor_col_max	; 0x16
; -----------------------------------------------------------------------------


; Only 1 font may be used
;%include 'ui/fonts/smol.fnt' ; 8x4
%include 'ui/fonts/baremetal.fnt' ; 12x6
;%include 'ui/fonts/departuremono.fnt' ; 14x7
;%include 'ui/fonts/ibm.fnt' ; 16x8

; Variables
align 16

VideoBase:		dq 0
LastLine:		dq 0
FG_Color:		dd 0x00FFFFFF	; White
BG_Color:		dd 0x00404040	; Dark grey
Line_Color:		dd 0x00F7CA54	; Return Infinity Yellow/Orange
Screen_Pixels:		dd 0
Screen_Bytes:		dd 0
VideoPPSL:		dd 0
VideoX:			dw 0
VideoY:			dw 0
Screen_Rows:		dw 0
Screen_Cols:		dw 0
Screen_Cursor_Row:	dw 0
Screen_Cursor_Col:	dw 0


; =============================================================================
; EOF
