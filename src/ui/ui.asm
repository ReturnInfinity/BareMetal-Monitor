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
;	mov al, '_'			; Cursor character
;	call output_char		; Output the cursor
;	call dec_cursor			; Set the cursor back by 1
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
;	push rax
;	mov al, 0x0E			; Cursor character
;	call output_char		; Output the cursor
;	pop rax
	call output_char		; Display char
	jmp ui_input_more

ui_input_backspace:
	test rcx, rcx			; backspace at the beginning? get a new char
	jz ui_input_more
	call output_char		; Output backspace as a character
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
	call [b_output]			; Output the required number of characters

	pop rcx
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; output_char -- Displays a char
;  IN:	AL  = char to display
; OUT:	All registers preserved
output_char:
	push rsi
	push rcx

	mov [tchar], al
	mov rsi, tchar
	mov ecx, 1
	call [b_output]

	pop rcx
	pop rsi
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


font_height: db 12
font_width: db 6
font_h equ 12
font_w equ 6

font_data:

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
