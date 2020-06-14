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

	; Calculate screen parameters
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

	; Set foreground/background color
	mov eax, 0x00FFFFFF
	mov [FG_Color], eax
	mov eax, 0x00404040
	mov [BG_Color], eax

	call screen_clear

	; Overwrite the kernel b_output function so output goes to the screen instead of the serial port
	mov rax, output_chars
	mov rdi, 0x100018
	stosq

	; Move cursor to bottom of screen
	mov ax, [Screen_Rows]
	dec ax
	mov [Screen_Cursor_Row], ax

	; Output system details
	mov rsi, cpumsg
	call output
	xor eax, eax
	mov rsi, 0x5012
	lodsw
	mov rdi, temp_string
	mov rsi, rdi
	call string_from_int
	call output
	mov rsi, coresmsg
	call output
	mov rsi, 0x5010
	lodsw
	mov rdi, temp_string
	mov rsi, rdi
	call string_from_int
	call output
	mov rsi, mhzmsg
	call output
	mov rsi, memmsg
	call output
	mov rsi, 0x5020
	lodsd
	mov rdi, temp_string
	mov rsi, rdi
	call string_from_int
	call output
	mov rsi, mibmsg
	call output
	mov rsi, closebracketmsg
	call output
	mov rsi, newline
	call output
	call output

poll:
	mov rsi, prompt
	call output
	mov rdi, temp_string
	mov rcx, 100
	call input
	; TODO clear leading/trailing spaces to sanitize input

	mov rsi, command_exec
	call string_compare
	jc exec

	mov rsi, command_dir
	call string_compare
	jc dir

	mov rsi, command_ver
	call string_compare
	jc print_ver

	mov rsi, command_load
	call string_compare
	jc load

	mov rsi, command_help
	call string_compare
	jc help

	cmp rcx, 0			; If no characters were entered show prompt again
	je poll
	mov rsi, message_unknown
	call output
	jmp poll

exec:
	call 0x200000
	jmp poll

dir:
	mov rsi, dirmsg
	call output
	mov rdi, temp_string
	mov rsi, rdi
	mov rax, 1
	mov rcx, 1
	mov rdx, 0
	call [b_disk_read]		; Load the 4K BMFS file table
	mov rax, 1
dir_next:
	cmp byte [rsi], 0		; 0 means we're at the end of the list
	je dir_end

	push rsi
	mov rdi, temp_string1
	mov rsi, rdi
	call string_from_int
	call output
	mov rsi, tab
	call output
	add al, 1
	pop rsi

	call output			; Output file name
	add rsi, 48
	push rax
	mov rax, [rsi]
	push rsi
	mov rsi, tab
	call output
	mov rdi, temp_string1
	mov rsi, rdi
	call string_from_int
	call output
	mov rsi, newline
	call output
	pop rsi
	pop rax
	add rsi, 16			; Next entry
	jmp dir_next
dir_end:
	jmp poll

print_ver:
	mov rsi, message_ver
	call output
	jmp poll

load:
	mov rsi, message_load
	call output
	mov rdi, temp_string
	mov rsi, rdi
	mov rcx, 2
	call input
	call string_to_int
	sub rax, 1			; Files are indexed from 0
	push rax			; Save the file #
	; check value
	; load file table
	mov rdi, temp_string
	mov rax, 1
	mov rcx, 1
	mov rdx, 0
	call [b_disk_read]
	; offset to file number and starting sector
	pop rcx				; Restore the file #
	shl rcx, 6
	add rcx, 32			; Offset to starting block # in BMFS file record
	add rdi, rcx
	mov rax, [rdi]
	shl rax, 9			; Shift left by 9 to convert 2M block to 4K sector
	; size
	; TODO
	; load to memory, use RAX for starting sector
	mov rdi, 0x200000
	mov rcx, 1			; Loading 4K for now
	mov rdx, 0
	call [b_disk_read]

	jmp poll

help:
	mov rsi, message_help
	call output
	jmp poll

; Strings

prompt:			db '> ', 0
message_ver:		db '1.0', 13, 0
message_load:		db 'Enter file number: ', 0
message_unknown:	db 'Unknown command', 13, 0
message_help:		db 'Available commands:', 13, ' dir  - Show programs currently on disk', 13, ' load - Load a program to memory (you will be prompted for the program number)', 13, ' exec - Run the program currently in memory', 13, ' ver  - Show the system version', 13, 0
command_exec:		db 'exec', 0
command_dir:		db 'dir', 0
command_ver:		db 'ver', 0
command_load:		db 'load', 0
command_help:		db 'help', 0
cpumsg:			db '[cpu: ', 0
memmsg:			db ']  [mem: ', 0
networkmsg:		db ']  [net: ', 0
diskmsg:		db ']  [hdd: ', 0
mibmsg:			db ' MiB', 0
mhzmsg:			db ' MHz', 0
coresmsg:		db ' x ', 0
namsg:			db 'N/A', 0
closebracketmsg:	db ']', 0
space:			db ' ', 0
newline:		db 13, 0
tab:			db 9, 0
dirmsg:			db '#       Name            Size', 13, '-----------------------------', 13, 0

; Variables

VideoBase:		dq 0
Screen_Pixels:		dd 0
Screen_Bytes:		dd 0
Screen_Row_2:		dd 0
FG_Color:		dd 0
BG_Color:		dd 0
VideoX:			dw 0
VideoY:			dw 0
Screen_Rows:		dw 0
Screen_Cols:		dw 0
Screen_Cursor_Row:	dw 0
Screen_Cursor_Col:	dw 0
VideoDepth:		db 0


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
	jnc input_halt			; No key entered... halt until an interrupt is received
	cmp al, 0x1C			; If Enter key pressed, finish
	je input_done
	cmp al, 0x0E			; Backspace
	je input_backspace
	cmp al, 32			; In ASCII range (32 - 126)?
	jl input_more
	cmp al, 126
	jg input_more
	cmp rcx, rdx			; Check if we have reached the max number of chars
	je input_more			; Jump if we have (should beep as well)
	stosb				; Store AL at RDI and increment RDI by 1
	inc rcx				; Increment the counter
	call output_char		; Display char
	jmp input_more

input_backspace:
	test rcx, rcx			; backspace at the beginning? get a new char
	jz input_more
	mov al, ' '			; 0x20 is the character for a space
	call output_char		; Write over the last typed character with the space
	call dec_cursor			; Decrement the cursor again
	call dec_cursor			; Decrement the cursor
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
	call output_newline

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
; output_newline -- Reset cursor to start of next line and scroll if needed
;  IN:	Nothing
; OUT:	All registers preserved
output_newline:
	push rax

	mov word [Screen_Cursor_Col], 0	; Reset column to 0
	mov ax, [Screen_Rows]		; Grab max rows on screen
	dec ax				; and subtract 1
	cmp ax, [Screen_Cursor_Row]	; Is the cursor already on the bottom row?
	je output_newline_scroll	; If so, then scroll
	inc word [Screen_Cursor_Row]	; If not, increment the cursor to next row
	jmp output_newline_done

output_newline_scroll:
	call screen_scroll

output_newline_done:
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
	call output_newline
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


; -----------------------------------------------------------------------------
; string_compare -- See if two strings match
;  IN:	RSI = string one
;	RDI = string two
; OUT:	Carry flag set if same
string_compare:
	push rsi
	push rdi
	push rbx
	push rax

string_compare_more:
	mov al, [rsi]			; Store string contents
	mov bl, [rdi]
	test al, al			; End of first string?
	jz string_compare_terminated
	cmp al, bl
	jne string_compare_not_same
	inc rsi
	inc rdi
	jmp string_compare_more

string_compare_not_same:
	pop rax
	pop rbx
	pop rdi
	pop rsi
	clc
	ret

string_compare_terminated:
	test bl, bl			; End of second string?
	jnz string_compare_not_same

	pop rax
	pop rbx
	pop rdi
	pop rsi
	stc
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; string_from_int -- Convert a binary integer into an string
;  IN:	RAX = binary integer
;	RDI = location to store string
; OUT:	RDI = points to end of string
;	All other registers preserved
; Min return value is 0 and max return value is 18446744073709551615 so the
; string needs to be able to store at least 21 characters (20 for the digits
; and 1 for the string terminator).
; Adapted from http://www.cs.usfca.edu/~cruse/cs210s09/rax2uint.s
string_from_int:
	push rdx
	push rcx
	push rbx
	push rax

	mov rbx, 10					; base of the decimal system
	xor ecx, ecx					; number of digits generated
string_from_int_next_divide:
	xor edx, edx					; RAX extended to (RDX,RAX)
	div rbx						; divide by the number-base
	push rdx					; save remainder on the stack
	inc rcx						; and count this remainder
	test rax, rax					; was the quotient zero?
	jnz string_from_int_next_divide			; no, do another division

string_from_int_next_digit:
	pop rax						; else pop recent remainder
	add al, '0'					; and convert to a numeral
	stosb						; store to memory-buffer
	loop string_from_int_next_digit			; again for other remainders
	xor al, al
	stosb						; Store the null terminator at the end of the string

	pop rax
	pop rbx
	pop rcx
	pop rdx
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; string_to_int -- Convert a string into a binary integer
;  IN:	RSI = location of string
; OUT:	RAX = integer value
;	All other registers preserved
; Adapted from http://www.cs.usfca.edu/~cruse/cs210s09/uint2rax.s
string_to_int:
	push rsi
	push rdx
	push rcx
	push rbx

	xor eax, eax			; initialize accumulator
	mov rbx, 10			; decimal-system's radix
string_to_int_next_digit:
	mov cl, [rsi]			; fetch next character
	cmp cl, '0'			; char precedes '0'?
	jb string_to_int_invalid	; yes, not a numeral
	cmp cl, '9'			; char follows '9'?
	ja string_to_int_invalid	; yes, not a numeral
	mul rbx				; ten times prior sum
	and rcx, 0x0F			; convert char to int
	add rax, rcx			; add to prior total
	inc rsi				; advance source index
	jmp string_to_int_next_digit	; and check another char

string_to_int_invalid:
	pop rbx
	pop rcx
	pop rdx
	pop rsi
	ret
; -----------------------------------------------------------------------------


%include 'font.inc'

temp_string1: times 50 db 0
temp_string2: times 50 db 0
temp_string: db 0

; =============================================================================
; EOF
