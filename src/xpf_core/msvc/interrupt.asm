; NoirVisor - Hardware-Accelerated Hypervisor solution
; 
; Copyright 2018-2023, Zero Tang. All rights reserved.
;
; This file is the host interrupt handler for NoirVisor.
;
; This program is distributed in the hope that it will be successful, but
; without any warranty (no matter implied warranty of merchantability or
; fitness for a particular purpose, etc.).
;
; File location: ./xpf_core/msvc/interrupt.asm

.code

hvtext segment readonly align(4096) read execute nopage

include noirhv.inc

extern nvc_vt_inject_nmi_to_subverted_host:proc

extern noir_divide_error_fault_handler:proc
extern noir_debug_fault_trap_handler:proc
extern noir_breakpoint_trap_handler:proc
extern noir_overflow_trap_handler:proc
extern noir_bound_range_fault_handler:proc
extern noir_invalid_opcode_fault_handler:proc
extern noir_device_not_available_fault_handler:proc
extern noir_double_fault_abort_handler:proc
extern noir_invalid_tss_fault_handler:proc
extern noir_segment_not_present_fault_handler:proc
extern noir_stack_fault_handler:proc
extern noir_general_protection_fault_handler:proc
extern noir_page_fault_handler:proc
extern noir_x87_floating_point_fault_handler:proc
extern noir_alignment_check_fault_handler:proc
extern noir_machine_check_abort_handler:proc
extern noir_simd_floating_point_fault_handler:proc
extern noir_control_protection_fault_handler:proc

nvc_vt_host_nmi_handler proc

	; In Intel VT-x, the NMI is not blocked while in Host Context.
	; Transfer the NMI to the guest if the host receives an NMI.
	; In other words, no registers can be destroyed in NMI handler of Intel VT-x.
	pushaq
	call nvc_vt_inject_nmi_to_subverted_host
	popaq
	; Use a special macro to return from NMI but do not unblock NMIs.
	nmiret

nvc_vt_host_nmi_handler endp

nvc_svm_host_nmi_handler proc

	; We do not handle NMI on ourself. NMI should be forwarded.
	; First of all, immediately disable interrupts globally.
	clgi
	; Use a special macro to return from NMI but do not unblock NMIs.
	nmiret
	; The arriving NMI is kept pending even if GIF is set later.

nvc_svm_host_nmi_handler endp

nvc_svm_host_ready_nmi proc

	; Set the GIF to unblock the NMI due to GIF.
	stgi
	; NMI should incur immediately after this instruction.
	; NMI has completed without unblocking NMIs here.
	; The return value is the stack.
	; Hypervisor must inject NMI to the guest once the
	; nested hypervisor enters vGIF=1 state.
	ret

nvc_svm_host_ready_nmi endp

noir_divide_error_fault_handler_a proc

	pushaq
	; Construct parameters for the exception handler.
	lea rcx,[rsp+gpr_stack_size]
	mov rdx,rsp
	; Call the handler.
	call noir_divide_error_fault_handler
	popaq
	iretq

noir_divide_error_fault_handler_a endp

noir_debug_fault_trap_handler_a proc

	pushaq
	; Construct parameters for the exception handler.
	lea rcx,[rsp+gpr_stack_size]
	mov rdx,rsp
	; Call the handler
	call noir_debug_fault_trap_handler
	popaq
	iretq

noir_debug_fault_trap_handler_a endp

noir_breakpoint_trap_handler_a proc

	pushaq
	; Construct parameters for the exception handler.
	lea rcx,[rsp+gpr_stack_size]
	mov rdx,rsp
	; Call the handler
	call noir_breakpoint_trap_handler
	popaq
	iretq

noir_breakpoint_trap_handler_a endp

noir_overflow_trap_handler_a proc

	pushaq
	; Construct parameters for the exception handler.
	lea rcx,[rsp+gpr_stack_size]
	mov rdx,rsp
	; Call the handler
	call noir_overflow_trap_handler
	popaq
	iretq

noir_overflow_trap_handler_a endp

noir_bound_range_fault_handler_a proc

	pushaq
	; Construct parameters for the exception handler.
	lea rcx,[rsp+gpr_stack_size]
	mov rdx,rsp
	; Call the handler
	call noir_bound_range_fault_handler
	popaq
	iretq

noir_bound_range_fault_handler_a endp

noir_invalid_opcode_fault_handler_a proc

	pushaq
	; Construct parameters for the exception handler.
	lea rcx,[rsp+gpr_stack_size]
	mov rdx,rsp
	; Call the handler
	call noir_invalid_opcode_fault_handler
	popaq
	iretq

noir_invalid_opcode_fault_handler_a endp

noir_device_not_available_fault_handler_a proc

	pushaq
	; Construct parameters for the exception handler.
	lea rcx,[rsp+gpr_stack_size]
	mov rdx,rsp
	; Call the handler
	call noir_device_not_available_fault_handler
	popaq
	iretq

noir_device_not_available_fault_handler_a endp

noir_double_fault_abort_handler_a proc

	pushaq
	; Construct parameters for the exception handler.
	lea rcx,[rsp+gpr_stack_size]
	mov rdx,rsp
	; Call the handler
	call noir_double_fault_abort_handler
	popaq
	; #DF has an error code. It must be popped out before the exception returns.
	add rsp,8
	iretq

noir_double_fault_abort_handler_a endp

noir_invalid_tss_fault_handler_a proc

	pushaq
	; Construct parameters for the exception handler
	lea rcx,[rsp+gpr_stack_size]
	mov rdx,rsp
	; Call the handler
	call noir_invalid_tss_fault_handler
	popaq
	; #TS has an error code. It must be popped out before the exception returns.
	add rsp,8
	iretq

noir_invalid_tss_fault_handler_a endp

noir_segment_not_present_fault_handler_a proc

	pushaq
	; Construct parameters for the exception handler
	lea rcx,[rsp+gpr_stack_size]
	mov rdx,rsp
	; Call the handler
	call noir_segment_not_present_fault_handler
	popaq
	; #NP has an error code. It must be popped out before the exception returns.
	add rsp,8
	iretq

noir_segment_not_present_fault_handler_a endp

noir_stack_fault_handler_a proc

	pushaq
	; Construct parameters for the exception handler
	lea rcx,[rsp+gpr_stack_size]
	mov rdx,rsp
	; Call the handler
	call noir_stack_fault_handler
	popaq
	; #SS has an error code. It must be popped out before the exception returns.
	add rsp,8
	iretq

noir_stack_fault_handler_a endp

noir_general_protection_fault_handler_a proc

	; #GP might occur when switching to invalid Guest state.
	pushaq
	; Construct parameters for the exception handler.
	lea rcx,[rsp+gpr_stack_size]	; The first parameter stores the exception frame.
	mov rdx,rsp						; The second parameter stores the GPR state.
	; Call the handler.
	call noir_general_protection_fault_handler
	popaq
	; #GP has an error code. It must be popped out before the exception returns.
	add rsp,8
	iretq

noir_general_protection_fault_handler_a endp

noir_page_fault_handler_a proc

	; #PF might occur when attempting to access guest memory.
	pushaq	; Save Registers.
	; Construct parameters for the exception handler.
	lea rcx,[rsp+gpr_stack_size]	; The first parameter stores the exception frame.
	mov rdx,rsp						; The second parameter stores the GPR state.
	; Call the handler.
	call noir_page_fault_handler
	popaq	; Restore Registers.
	; #PF has an error code. It must be popped out before the exception returns.
	add rsp,8
	iretq

noir_page_fault_handler_a endp

noir_x87_floating_point_fault_handler_a proc

	pushaq
	; Construct parameters for the exception handler
	lea rcx,[rsp+gpr_stack_size]
	mov rdx,rsp
	; Call the handler
	call noir_x87_floating_point_fault_handler
	popaq
	iretq

noir_x87_floating_point_fault_handler_a endp

noir_alignment_check_fault_handler_a proc

	pushaq
	; Construct parameters for the exception handler
	lea rcx,[rsp+gpr_stack_size]
	mov rdx,rsp
	; Call the handler
	call noir_alignment_check_fault_handler
	popaq
	; #AC has an error code. It must be popped out before the exception returns.
	add rsp,8
	iretq

noir_alignment_check_fault_handler_a endp

noir_machine_check_abort_handler_a proc

	pushaq
	; Construct parameters for the exception handler
	lea rcx,[rsp+gpr_stack_size]
	mov rdx,rsp
	; Call the handler
	call noir_machine_check_abort_handler
	popaq
	iretq

noir_machine_check_abort_handler_a endp

noir_simd_floating_point_fault_handler_a proc

	pushaq
	; Construct parameters for the exception handler
	lea rcx,[rsp+gpr_stack_size]
	mov rdx,rsp
	; Call the handler
	call noir_simd_floating_point_fault_handler
	popaq
	iretq

noir_simd_floating_point_fault_handler_a endp

noir_control_protection_fault_handler_a proc

	pushaq
	; Construct parameters for the exception handler
	lea rcx,[rsp+gpr_stack_size]
	mov rdx,rsp
	; Call the handler
	call noir_control_protection_fault_handler
	popaq
	; #DF has an error code. It must be popped out before the exception returns.
	add rsp,8
	iretq

noir_control_protection_fault_handler_a endp

hvtext ends

end