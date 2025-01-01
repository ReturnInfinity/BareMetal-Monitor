; =============================================================================
; BareMetal Monitor
; Copyright (C) 2008-2025 Return Infinity -- see LICENSE.TXT
;
; This file contains all of the functions for the monitor CLI. It must be
; attached to the end of the BareMetal kernel.
; =============================================================================


BITS 64
ORG 0x001E0000
MONITORSIZE equ 8192			; Pad Monitor to this length

%include 'api/libBareMetal.asm'

start:
	cmp byte [firstrun], 1		; Check if the first run flag is set
	jne poll			; If not, jump to poll
	call ui_init			; Otherwise run ui_init
	mov byte [firstrun], 0		; And clear the first run flag

	; Move RAM drive image to proper location (if it was provided)
	cmp byte [0x410000], 0		; Check for a non-zero value
	je skip_ramdrive		; If zero, then there is no RAM drive image
	mov rsi, 0x00110104		; Kernel value for MemAmount
	mov eax, [rsi]
	sub eax, 2			; Remove 2 MiB of available RAM
	mov [rsi], eax
	; Crawl the upper page map and remove the highest 2MiB page
	mov rsi, 0x20000
check_next:
	mov rbx, rax
	lodsq
	cmp rax, 0
	jne check_next
	xor bl, bl
	mov [RAMDriveLocation], rbx
	xor eax, eax
	sub rsi, 16			; Jump back to the last valid record
	mov [rsi], rax			; Overwrite it
	mov rsi, 0x410000		; Copy RAM Drive image from here
	mov rdi, rbx			; to here
	mov rcx, 262144			; 2MiB's worth of quadwords
	rep movsq
skip_ramdrive:

	; Output system details

	; Output core count and speed
	mov rsi, cpumsg
	call ui_output
	xor eax, eax
	mov rsi, 0x5012
	lodsw
	mov rdi, temp_string
	mov rsi, rdi
	call string_from_int
	call ui_output
	mov rsi, coresmsg
	call ui_output
	mov rsi, 0x5010
	lodsw
	mov rdi, temp_string
	mov rsi, rdi
	call string_from_int
	call ui_output
	mov rsi, mhzmsg
	call ui_output

	; Output memory size
	mov rsi, memmsg
	call ui_output
	mov rsi, 0x00110104		; Kernel value for MemAmount
	lodsd
	mov rdi, temp_string
	mov rsi, rdi
	call string_from_int
	call ui_output
	mov rsi, mibmsg
	call ui_output

	; Output MAC address
	mov rsi, networkmsg
	call ui_output
	mov rcx, MAC_GET
	call [b_system]
	ror rax, 40
	mov ecx, 5			; Display the first 5 with separators after
nextMAC:
	call dump_al
	mov rsi, macsep
	call ui_output
	rol rax, 8
	sub ecx, 1
	test ecx, ecx
	jnz nextMAC
	call dump_al			; Display the last
	mov rsi, closebracketmsg
	call ui_output

	mov rsi, newline
	call ui_output

	; Write a 'ret' opcode to the start of program memory
	mov rdi, [ProgramLocation]
	mov al, 0xc3			; 'ret' opcode
	stosb

	; Detect file system
	mov rax, 0			; First sector
	add rax, 32768
	mov rcx, 1			; One 4K sector
	mov rdx, 0			; Drive 0
	mov rdi, temp_string
	mov rsi, rdi
	call [b_storage_read]
	mov eax, [rsi+1024]
	cmp eax, 0x53464d42		; "BMFS"
	je bmfs
	jmp poll

bmfs:
	mov al, 'B'
	mov [FSType], al

	; Detect if there is an 'init.app' on the filesystem
	mov rdi, temp_string
	mov rsi, rdi
	mov rax, 1
	add rax, [UEFI_Disk_Offset]
	mov rcx, 1
	mov rdx, 0
	call [b_storage_read]		; Load the 4K BMFS file table
	mov rsi, initapp
	sub rdi, 64
bmfs_next:
	add rdi, 64
	cmp byte [rdi], 0
	je poll
	call string_compare
	jnc bmfs_next
	; There is an 'init.app' program, load and execute it
	add rdi, 32			; Offset to starting block # in BMFS file record
	mov rax, [rdi]
	shl rax, 9			; Shift left by 9 to convert 2M block to 4K sector
	add rdi, 16			; Skip to File Size value
	mov rcx, [rdi]			; File size in bytes
	; load to memory, use RAX for starting sector
	add rax, [UEFI_Disk_Offset]
	mov rdi, [ProgramLocation]
	add rcx, 4095			; Add 1-byte less of a full sector amount
	shr rcx, 12			; Quick divide by 4096
	mov rdx, 0
	call [b_storage_read]		; Load program
	call [ProgramLocation]		; Execute program

poll:
	mov rsi, newline
	call ui_output
poll_nonewline:
	mov rsi, prompt
	call ui_output
	mov rdi, temp_string
	mov rcx, 100
	call ui_input
	jrcxz poll			; input stores the number of characters received in RCX
	mov rsi, rdi
	call string_parse		; Remove extra spaces
	jrcxz poll			; string_parse stores the number of words in RCX
	mov byte [args], cl		; Store the number of words in the string
	; Break the contents of temp_string into individual strings
	mov al, 0x20
	xor bl, bl
	call string_change_char

	mov rsi, command_exec
	call string_compare
	jc exec

	mov rsi, command_cls
	call string_compare
	jc cls

	mov rsi, command_dir
	call string_compare
	jc dir

	mov rsi, command_dump
	call string_compare
	jc dump

	mov rsi, command_ver
	call string_compare
	jc print_ver

	mov rsi, command_load
	call string_compare
	jc load

	mov rsi, command_loadr
	call string_compare
	jc loadr

	mov rsi, command_peek
	call string_compare
	jc peek

	mov rsi, command_poke
	call string_compare
	jc poke

	mov rsi, command_help
	call string_compare
	jc help

	mov rsi, command_test
	call string_compare
	jc testzone

	mov rsi, command_shutdown
	call string_compare
	jc shutdown

	mov rsi, message_unknown
	call ui_output
	jmp poll

testzone:
	xor ecx, ecx
	div ecx
;	xor eax, eax			; Zero RAX for the packet counter
;	mov [0x1e8000], rax		; Store it to a temp location
;tst_loop:
;	call [b_input]			; Check if there was a key pressed
;	jnz poll			; If so, jmp to the main loop
;	mov rdi, temp_string		; Temp location to store the packet
;	call [b_net_rx]			; Returns bytes received in RCX, Zero flag set on no bytes
;	jz tst_loop_nodata		; In nothing was received skip incrementing the counter
;	add qword [0x1e8000], 1		; Increment the packet counter
;tst_loop_nodata:
;	jmp tst_loop
	jmp poll

shutdown:
	mov rcx, SHUTDOWN
	call [b_system]

exec:
	call [ProgramLocation]
	jmp poll

cls:
	call screen_clear
	jmp poll_nonewline

dir:
	mov rax, [RAMDriveLocation]
	cmp rax, 0
	je dir_skipramfs

dir_ramfs:
	mov rsi, dirmsgramfs
	call ui_output
	mov rsi, dirmsg
	call ui_output
	mov rsi, [RAMDriveLocation]
	mov rax, 1

dir_ramfs_next:
	cmp byte [rsi], 0		; 0 means we're at the end of the list
	je dir_ramfs_end
	push rsi
	mov rsi, newline
	call ui_output
	mov rdi, temp_string1
	mov rsi, rdi
	call string_from_int
	call ui_output
	mov rsi, tab
	call ui_output
	add al, 1
	pop rsi

	call ui_output			; Output file name
	add rsi, 48
	push rax
	mov rax, [rsi]
	push rsi
	mov rsi, tab
	call ui_output
	mov rdi, temp_string1
	mov rsi, rdi
	call string_from_int
	call ui_output
	pop rsi
	pop rax
	add rsi, 16			; Next entry
	jmp dir_ramfs_next

dir_ramfs_end:

dir_skipramfs:
	mov al, [FSType]
	cmp al, 0
	je noFS

dir_bmfs:
	mov rsi, dirmsgbmfs
	call ui_output
	mov rsi, dirmsg
	call ui_output
	mov rdi, temp_string
	mov rsi, rdi
	mov rax, 1
	add rax, [UEFI_Disk_Offset]
	mov rcx, 1
	mov rdx, 0
	call [b_storage_read]		; Load the 4K BMFS file table
	mov rax, 1

dir_bmfs_next:
	cmp byte [rsi], 0		; 0 means we're at the end of the list
	je dir_bmfs_end
	push rsi
	mov rsi, newline
	call ui_output
	mov rdi, temp_string1
	mov rsi, rdi
	call string_from_int
	call ui_output
	mov rsi, tab
	call ui_output
	add al, 1
	pop rsi

	call ui_output			; Output file name
	add rsi, 48
	push rax
	mov rax, [rsi]
	push rsi
	mov rsi, tab
	call ui_output
	mov rdi, temp_string1
	mov rsi, rdi
	call string_from_int
	call ui_output
	pop rsi
	pop rax
	add rsi, 16			; Next entry
	jmp dir_bmfs_next
dir_bmfs_end:
	jmp poll

print_ver:
	mov rsi, message_ver
	call ui_output
	jmp poll

load:
	mov al, [FSType]
	cmp al, 0
	je noFS

load_bmfs:
	mov rsi, message_load
	call ui_output
	mov rdi, temp_string
	mov rsi, rdi
	mov rcx, 2
	call ui_input
	call string_to_int
	sub rax, 1			; Files are indexed from 0
	push rax			; Save the file #
	; check value
	; load file table
	mov rdi, temp_string
	mov rax, 1
	add rax, [UEFI_Disk_Offset]
	mov rcx, 1
	mov rdx, 0
	call [b_storage_read]
	; offset to file number, starting sector, and file size
	pop rcx				; Restore the file #
	shl rcx, 6
	add rdi, rcx			; RDI points to start of BMFS entry
	mov al, [rdi]			; Load first character of file name
	cmp al, 1			; 0x00 or 0x01 are invalid
	jle load_notfound
	add rdi, 32			; Offset to starting block # in BMFS file record
	mov rax, [rdi]
	shl rax, 9			; Shift left by 9 to convert 2M block to 4K sector
	add rdi, 16			; Skip to File Size value
	mov rcx, [rdi]			; File size in bytes
	cmp rcx, 0			; Is the file empty?
	je poll				; If so, no need to load it
	; load to memory, use RAX for starting sector
	add rax, [UEFI_Disk_Offset]
	mov rdi, [ProgramLocation]
	add rcx, 4095			; Add 1-byte less of a full sector amount
	shr rcx, 12			; Quick divide by 4096
	mov rdx, 0
	call [b_storage_read]
	jmp poll

load_notfound:
	mov rsi, invalidargs
	call ui_output
	jmp poll

noFS:
	mov rsi, message_noFS
	call ui_output
	jmp poll

loadr:
	mov rsi, message_load
	call ui_output
	mov rdi, temp_string
	mov rsi, rdi
	mov rcx, 2
	call ui_input
	call string_to_int
	sub rax, 1			; Files are indexed from 0
	mov rcx, rax			; File #
	mov rsi, [RAMDriveLocation]
	shl rcx, 6
	add rsi, rcx			; RDI points to start of BMFS entry
	mov al, [rsi]			; Load first character of file name
	cmp al, 1			; 0x00 or 0x01 are invalid
	jle load_notfound
	add rsi, 32			; Offset to starting block # in BMFS file record
	mov rax, [rsi]			; Starting block
	shl rax, 10			; Shift left by 10 to convert to 1K Blocks
	add rsi, 16			; Skip to File Size value
	mov rcx, [rsi]			; File size in bytes
	cmp rcx, 0			; Is the file empty?
	je poll				; If so, no need to load it
	; Copy RAM drive file to program RAM
	mov rsi, [RAMDriveLocation]
	add rsi, rax
	mov rdi, [ProgramLocation]
	rep movsb
	jmp poll
	
	
dump:
	cmp byte [args], 4
	jl insuf
	jg toomany

	; Parse the starting memory address
	mov rsi, temp_string
	call string_length
	add rsi, 1
	add rsi, rcx
	call hex_string_to_int		; RAX holds the address
	mov r8, rax			; Save it to RBX

	; Parse the number of values to display
	call string_length
	add rsi, 1
	add rsi, rcx
	call hex_string_to_int
	mov r9, rax

	; Parse the size of each value to display
	call string_length
	add rsi, 1
	add rsi, rcx
	call hex_string_to_int

	mov rsi, r8
	mov rcx, r9
	xor edx, edx			; Counter for line output

	cmp al, 1
	je dump_b
	cmp al, 2
	je dump_w
	cmp al, 4
	je dump_d
	cmp al, 8
	je dump_q
	mov rsi, invalidargs
	call ui_output
	jmp poll

dump_b:
	push rsi
	mov rsi, newline
	call ui_output
	pop rsi
	mov rax, rsi
	call dump_rax			; Display the memory address
	push rsi
	mov rsi, dumpsep
	call ui_output			; Display ": "
	pop rsi
	mov rdi, dump_b_chars
dump_b_next:
	cmp dl, 0x10			; 16 bytes per line
	je dump_b_newline		; Display a newline if we are over the limit
	lodsb
	call dump_al			; Dump the byte
	and al, 0x7F			; Clear highest character bit
	cmp al, 32
	jg dump_b_next_write_char	; Is it between 33 and 127?
	mov al, 0x20			; If not, set AL to space
dump_b_next_write_char:
	stosb
	inc dl				; Increment our counter of values per line
	push rsi
	mov rsi, space
	call ui_output
	pop rsi
	dec rcx				; Decrement the number of bytes left to output
	jnz dump_b_next
	mov rsi, dump_b_string
	call ui_output
	jmp dump_end
dump_b_newline:
	mov rdi, dump_b_chars
	push rsi
	mov rsi, dump_b_string
	call ui_output
	pop rsi
	xor edx, edx			; Reset the value counter
	jmp dump_b

dump_w:
	push rsi
	mov rsi, newline
	call ui_output
	pop rsi
	mov rax, rsi
	call dump_rax
	push rsi
	mov rsi, dumpsep
	call ui_output
	pop rsi
dump_w_next:
	cmp dl, 0x8			; 8 words per line
	je dump_w_newline
	lodsw
	call dump_ax
	inc dl
	push rsi
	mov rsi, space
	call ui_output
	pop rsi
	dec rcx
	jnz dump_w_next
	jmp dump_end
dump_w_newline:
	xor edx, edx
	jmp dump_w

dump_d:
	push rsi
	mov rsi, newline
	call ui_output
	pop rsi
	mov rax, rsi
	call dump_rax
	push rsi
	mov rsi, dumpsep
	call ui_output
	pop rsi
dump_d_next:
	cmp dl, 0x4			; 4 double words per line
	je dump_d_newline
	lodsd
	call dump_eax
	inc dl
	push rsi
	mov rsi, space
	call ui_output
	pop rsi
	dec rcx
	jnz dump_d_next
	jmp dump_end
dump_d_newline:
	xor edx, edx
	jmp dump_d

dump_q:
	push rsi
	mov rsi, newline
	call ui_output
	pop rsi
	mov rax, rsi
	call dump_rax
	push rsi
	mov rsi, dumpsep
	call ui_output
	pop rsi
dump_q_next:
	cmp dl, 0x2			; 2 quad words per line
	je dump_q_newline
	lodsq
	call dump_rax
	inc dl
	push rsi
	mov rsi, space
	call ui_output
	pop rsi
	dec rcx
	jnz dump_q_next
	jmp dump_end
dump_q_newline:
	xor edx, edx
	jmp dump_q

dump_end:
	jmp poll

peek:
	cmp byte [args], 3
	jl insuf
	jg toomany
	push rsi
	mov rsi, newline
	call ui_output
	pop rsi
	mov rsi, temp_string
	call string_length
	add rsi, 1
	add rsi, rcx
	call hex_string_to_int		; RAX holds the address
	mov rbx, rax			; Save it to RBX

	call string_length
	add rsi, 1
	add rsi, rcx
	call hex_string_to_int		; RAX holds the bytes
	cmp al, 1
	je peek_b
	cmp al, 2
	je peek_w
	cmp al, 4
	je peek_d
	cmp al, 8
	je peek_q
	mov rsi, invalidargs
	call ui_output
	jmp poll

peek_b:
	mov rsi, rbx
	lodsb
	call dump_al
	jmp peek_end

peek_w:
	mov rsi, rbx
	lodsw
	call dump_ax
	jmp peek_end

peek_d:
	mov rsi, rbx
	lodsd
	call dump_eax
	jmp peek_end

peek_q:
	mov rsi, rbx
	lodsq
	call dump_rax
	jmp peek_end

peek_end:
	jmp poll

poke:
	cmp byte [args], 3
	jl insuf
	jg toomany
	
	mov rsi, temp_string
	call string_length
	add rsi, 1
	add rsi, rcx
	call hex_string_to_int		; RAX holds the address
	mov rbx, rax			; Save it to RBX

	call string_length
	add rsi, 1
	add rsi, rcx
	call string_length
	call hex_string_to_int
	cmp cl, 2
	je poke_b
	cmp cl, 4
	je poke_w
	cmp cl, 8
	je poke_d
	cmp cl, 16
	je poke_q
	mov rsi, invalidargs
	call ui_output
	jmp poll

poke_b:
	mov rdi, rbx
	stosb
	jmp poke_end

poke_w:
	mov rdi, rbx
	stosw
	jmp poke_end

poke_d:
	mov rdi, rbx
	stosd
	jmp poke_end

poke_q:
	mov rdi, rbx
	stosq
	jmp poke_end

poke_end:
	jmp poll

help:
	mov rsi, message_help
	call ui_output
	jmp poll

insuf:
	mov rsi, insufargs
	call ui_output
	jmp poll

toomany:
	mov rsi, toomanyargs
	call ui_output
	jmp poll


; Internal functions

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
; string_chomp -- Strip leading and trailing spaces from a string
;  IN:	RSI = string location
; OUT:	All registers preserved
string_chomp:
	push rsi
	push rdi
	push rcx
	push rax

	call string_length		; Quick check to see if there are any characters in the string
	jrcxz string_chomp_done	; No need to work on it if there is no data

	mov rdi, rsi			; RDI will point to the start of the string...
	push rdi			; ...while RSI will point to the "actual" start (without the spaces)
	add rdi, rcx			; os_string_length stored the length in RCX

string_chomp_findend:			; we start at the end of the string and move backwards until we don't find a space
	dec rdi
	cmp rsi, rdi			; Check to make sure we are not reading backward past the string start
	jg string_chomp_fail		; If so then fail (string only contained spaces)
	cmp byte [rdi], ' '
	je string_chomp_findend

	inc rdi				; we found the real end of the string so null terminate it
	mov byte [rdi], 0x00
	pop rdi

string_chomp_start_count:		; read through string until we find a non-space character
	cmp byte [rsi], ' '
	jne string_chomp_copy
	inc rsi
	jmp string_chomp_start_count

string_chomp_fail:			; In this situation the string is all spaces
	pop rdi				; We are about to bail out so make sure the stack is sane
	xor al, al
	stosb
	jmp string_chomp_done

; At this point RSI points to the actual start of the string (minus the leading spaces, if any)
; And RDI point to the start of the string

string_chomp_copy:			; Copy a byte from RSI to RDI one byte at a time until we find a NULL
	lodsb
	stosb
	test al, al
	jnz string_chomp_copy

string_chomp_done:
	pop rax
	pop rcx
	pop rdi
	pop rsi
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; string_parse -- Parse a string into individual words
;  IN:	RSI = Address of string
; OUT:	RCX = word count
; Note:	This function will remove "extra" white-space in the source string
;	"This is  a test. " will update to "This is a test."
string_parse:
	push rsi
	push rdi
	push rax

	xor ecx, ecx			; RCX is our word counter
	mov rdi, rsi

	call string_chomp		; Remove leading and trailing spaces

	cmp byte [rsi], 0x00		; Check the first byte
	je string_parse_done		; If it is a null then bail out
	inc rcx				; At this point we know we have at least one word

string_parse_next_char:
	lodsb
	stosb
	test al, al			; Check if we are at the end
	jz string_parse_done		; If so then bail out
	cmp al, ' '			; Is it a space?
	je string_parse_found_a_space
	jmp string_parse_next_char	; If not then grab the next char

string_parse_found_a_space:
	lodsb				; We found a space.. grab the next char
	cmp al, ' '			; Is it a space as well?
	jne string_parse_no_more_spaces
	jmp string_parse_found_a_space

string_parse_no_more_spaces:
	dec rsi				; Decrement so the next lodsb will read in the non-space
	inc rcx
	jmp string_parse_next_char

string_parse_done:
	pop rax
	pop rdi
	pop rsi
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; string_change_char -- Change all instances of a character in a string
;  IN:	RSI = string location
;	AL  = character to replace
;	BL  = replacement character
; OUT:	All registers preserved
string_change_char:
	push rsi
	push rcx
	push rbx
	push rax

	mov cl, al
string_change_char_loop:
	mov byte al, [rsi]
	test al, al
	jz string_change_char_done
	cmp al, cl
	jne string_change_char_no_change
	mov byte [rsi], bl

string_change_char_no_change:
	inc rsi
	jmp string_change_char_loop

string_change_char_done:
	pop rax
	pop rbx
	pop rcx
	pop rsi
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

	mov rbx, 10			; base of the decimal system
	xor ecx, ecx			; number of digits generated
string_from_int_next_divide:
	xor edx, edx			; RAX extended to (RDX,RAX)
	div rbx				; divide by the number-base
	push rdx			; save remainder on the stack
	inc rcx				; and count this remainder
	test rax, rax			; was the quotient zero?
	jnz string_from_int_next_divide	; no, do another division

string_from_int_next_digit:
	pop rax				; else pop recent remainder
	add al, '0'			; and convert to a numeral
	stosb				; store to memory-buffer
	loop string_from_int_next_digit	; again for other remainders
	xor al, al
	stosb				; Store the null terminator at the end of the string

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


; -----------------------------------------------------------------------------
; hex_string_to_int -- Convert up to 8 hexascii to bin
;  IN:	RSI = Location of hex asciiz string
; OUT:	RAX = binary value of hex string
;	All other registers preserved
hex_string_to_int:
	push rsi
	push rcx
	push rbx

	xor ebx, ebx
hex_string_to_int_loop:
	lodsb
	mov cl, 4
	cmp al, 'a'
	jb hex_string_to_int_ok
	sub al, 0x20			; convert to upper case if alpha
hex_string_to_int_ok:
	sub al, '0'			; check if legal
	jc hex_string_to_int_exit	; jump if out of range
	cmp al, 9
	jle hex_string_to_int_got	; jump if number is 0-9
	sub al, 7			; convert to number from A-F or 10-15
	cmp al, 15			; check if legal
	ja hex_string_to_int_exit	; jump if illegal hex char
hex_string_to_int_got:
	shl rbx, cl
	or bl, al
	jmp hex_string_to_int_loop
hex_string_to_int_exit:
	mov rax, rbx			; integer value stored in RBX, move to RAX

	pop rbx
	pop rcx
	pop rsi
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; dump_(rax|eax|ax|al) -- Dump content of RAX, EAX, AX, or AL
;  IN:	RAX = content to dump
; OUT:	Nothing, all registers preserved
dump_rax:
	rol rax, 8
	call dump_al
	rol rax, 8
	call dump_al
	rol rax, 8
	call dump_al
	rol rax, 8
	call dump_al
	rol rax, 32
dump_eax:
	rol eax, 8
	call dump_al
	rol eax, 8
	call dump_al
	rol eax, 16
dump_ax:
	rol ax, 8
	call dump_al
	rol ax, 8
dump_al:
	push rbx
	push rax
	mov rbx, hextable
	push rax			; Save RAX since we work in 2 parts
	shr al, 4			; Shift high 4 bits into low 4 bits
	xlatb
	mov [tchar+0], al
	pop rax
	and al, 0x0f			; Clear the high 4 bits
	xlatb
	mov [tchar+1], al
	push rsi
	push rcx
	mov rsi, tchar
	call ui_output
	pop rcx
	pop rsi
	pop rax
	pop rbx
	ret

hextable:		db '0123456789ABCDEF'
; -----------------------------------------------------------------------------

; Strings

prompt:			db '> ', 0
message_ver:		db 10, '1.0', 0
message_load:		db 10, 'Enter file number: ', 0
message_unknown:	db 10, 'Unknown command', 0
message_noFS:		db 10, 'No filesystem detected', 0
message_help:		db 10, 'Available commands:', 10, 'cls  - clear the screen', 10, 'dir  - Show programs currently on disk', 10, 'load - Load a program to memory (you will be prompted for the program number)', 10, 'exec - Run the program currently in memory', 10, 'ver  - Show the system version', 10, 'peek - hex mem address and bytes (1, 2, 4, or 8) - ex "peek 200000 8" to read 8 bytes', 10, 'poke - hex mem address and hex value (1, 2, 4, or 8 bytes) - ex "poke 200000 00ABCDEF" to write 4 bytes', 10, 'dump - hex mem address, hex amount, bytes (1, 2, 4, or 8) - ex "dump 100000 10 4"', 0
command_exec:		db 'exec', 0
command_cls:		db 'cls', 0
command_dir:		db 'dir', 0
command_dump:		db 'dump', 0
command_ver:		db 'ver', 0
command_load:		db 'load', 0
command_loadr:		db 'loadr', 0
command_peek:		db 'peek', 0
command_poke:		db 'poke', 0
command_help:		db 'help', 0
command_test:		db 'test', 0
command_shutdown:	db 'shutdown', 0
cpumsg:			db '[cpu: ', 0
memmsg:			db ']  [mem: ', 0
networkmsg:		db ']  [net: ', 0
diskmsg:		db ']  [hdd: ', 0
mibmsg:			db ' MiB free', 0
mhzmsg:			db ' MHz', 0
coresmsg:		db ' x ', 0
namsg:			db 'N/A', 0
closebracketmsg:	db ']', 0
space:			db ' ', 0
macsep:			db ':', 0
dumpsep:		db ': ', 0
newline:		db 10, 0
tab:			db 9, 0
insufargs:		db 10, 'Insufficient argument(s)', 0
toomanyargs:		db 10, 'Too many arguments', 0
invalidargs:		db 10, 'Invalid argument(s)', 0
dirmsg:			db 10, '#       Name            Size', 10, '-----------------------------', 0
dirmsgbmfs:		db 10, 'BMFS', 0
dirmsgramfs:		db 10, 'RAMFS', 0
initapp:		db 'init.app', 0
dump_b_string:		db ' | '
dump_b_chars:		db '                ', 0

; Variables
align 16
ProgramLocation:	dq 0xFFFF800000000000
RAMDriveLocation:	dq 0
UEFI_Disk_Offset:	dq 32768
args:			db 0
FSType: 		db 0		; File System
firstrun:		db 1		; A flag for running ui_init only once


%include 'ui/ui.asm'

; Temporary data
tchar: db 0, 0, 0
temp_string1: times 50 db 0
temp_string2: times 50 db 0
align 16
temp_string: db 0

times MONITORSIZE-($-$$) db 0x90	; Set the compiled monitor to at least this size in bytes
; =============================================================================
; EOF
