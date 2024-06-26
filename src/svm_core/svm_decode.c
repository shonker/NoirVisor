/*
  NoirVisor - Hardware-Accelerated Hypervisor solution

  Copyright 2018-2024, Zero Tang. All rights reserved.

  This file decodes interceptions if Decode-Assist and/or Next-RIP are unsupported.

  This program is distributed in the hope that it will be useful, but 
  without any warranty (no matter implied warranty or merchantability
  or fitness for a particular purpose, etc.).

  File Location: /svm_core/svm_exit.c
*/

#include <nvdef.h>
#include <nvbdk.h>
#include <nvstatus.h>
#include <noirhvm.h>
#include <svm_intrin.h>
#include <nv_intrin.h>
#include <amd64.h>
#include <ci.h>
#include "svm_vmcb.h"
#include "svm_npt.h"
#include "svm_exit.h"
#include "svm_def.h"

// This module is built because Linux KVM does not support Decode-Assist.

// This is a callback function to translate GPA to HPA.
bool nvc_svm_translate_custom_gpa(u64 pt,u32 level,u64 gpa,u32 access,u64p hpa,noir_page_fault_error_code_p err_code)
{
	const u64 shift_diff=(level-1)*page_shift_diff64;
	const u64 index=page_entry_index64(gpa>>(shift_diff+page_4kb_shift));
	amd64_npt_general_entry_p table=(amd64_npt_general_entry_p)pt;
	// Check permission.
	err_code->value=0;
	err_code->present=table[index].present<noir_bt(&access,noir_cvm_map_gpa_read);
	err_code->write=table[index].write<noir_bt(&access,noir_cvm_map_gpa_write);
	err_code->execute=table[index].no_execute>noir_bt(&access,noir_cvm_map_gpa_execute);
	if(err_code->value)
	{
		nvd_printf("[SVM-GPA Translation] Permission is not granted at level %u! #PF Error: 0x%X\n",level,err_code->value);
		return false;
	}
	else
	{
		// Permission is granted.
		if(level>1)
		{
			// This is either large-parge or has sub-levels.
			if(table[index].psize)
			{
				const u64 offset_mask=(1<<(shift_diff+page_4kb_shift))-1;
				const u64 base=(table[index].base>>shift_diff)<<(shift_diff+page_4kb_shift);
				nvd_printf("[SVM-GPA Translate] GPA 0x%016llX is translated into HPA 0x%016llX at level %u!\n",gpa,*hpa,level);
				*hpa=base+(gpa&offset_mask);
				return true;
			}
			else
			{
				const u64 base=page_4kb_mult(table[index].base);
				nvd_printf("[SVM-GPA Translate] Base of Next Level (%u): 0x%016llX\n",level-1,base);
				return nvc_svm_translate_custom_gpa(base,level-1,gpa,access,hpa,err_code);
			}
		}
		else
		{
			// Final Level
			const u64 base=page_4kb_mult(table[index].base);
			*hpa=base+page_offset(gpa);
			nvd_printf("[SVM-GPA Translate] GPA 0x%016llX is translated into HPA 0x%016llX!\n",gpa,*hpa);
			return true;
		}
	}
}

// Fetched instruction bytes will be placed in VMCB.
void static nvc_svm_fetch_instruction(noir_svm_vcpu_p vcpu,noir_svm_custom_vcpu_p cvcpu)
{
	if(cvcpu)
	{
		// Guest information
		const void* vmcb=cvcpu->vmcb.virt;
		const u64 ncr3=noir_svm_vmread64(vmcb,npt_cr3);
		const u64 gcr3=noir_svm_vmread64(vmcb,guest_cr3);
		const u64 grip=noir_svm_vmread64(vmcb,guest_rip);
		const u16 gcss=noir_svm_vmread16(vmcb,guest_cs_selector);
		const u64 gcsb=noir_svm_vmread64(vmcb,guest_cs_base);
		const u64 gip=gcsb+grip;
		// CR0, CR3, CR4 and EFER will be consulted in order to fetch guest memory.
		cvcpu->header.crs.cr0=noir_svm_vmread64(vmcb,guest_cr0);
		cvcpu->header.crs.cr3=noir_svm_vmread64(vmcb,guest_cr3);
		cvcpu->header.crs.cr4=noir_svm_vmread64(vmcb,guest_cr4);
		cvcpu->header.msrs.efer=noir_svm_vmread64(vmcb,guest_efer);
		// Fetch instruction bytes from CVM.
		u8p ins_bytes=(u8p)((ulong_ptr)vmcb+guest_instruction_bytes);
		u32 error_code=0;
		size_t copied_length=nvc_copy_guest_virtual_memory(&cvcpu->header,grip,(void*)ins_bytes,15,false,&error_code);
		if(copied_length<15)
			nvd_printf("[Software Fetcher] Note: Instruction is near page boundary! rip=0x%016llX\n",grip);
		char ins_byte_str[48];
		for(size_t i=0;i<copied_length;i++)
			nv_snprintf(&ins_byte_str[i*3],sizeof(ins_byte_str)-(i*3),"%02X ",ins_bytes[i]);
		nvd_printf("[Software Fetcher] Fetched instruction bytes from CVM Guest at %04X:%016llX:\n%s\n",gcss,grip,ins_byte_str);
	}
	else
	{
		// Guest information
		const void* vmcb=vcpu->vmcb.virt;
		const u64 gcr3=noir_svm_vmread64(vmcb,guest_cr3);
		const u64 grip=noir_svm_vmread64(vmcb,guest_rip);
		const u64 gcsb=noir_svm_vmread64(vmcb,guest_cs_base);
		const u64 gip=gcsb+grip;
		// Fetch instruction bytes from Host
		u8p ins_bytes=(u8p)((ulong_ptr)vmcb+guest_instruction_bytes);
		u32 error_code=0;
		// For the sake of universal safety, do not load cr3 into the processor.
		size_t len=nvc_copy_host_virtual_memory64(gcr3,gip,ins_bytes,15,false,noir_svm_vmcb_bt32(vmcb,guest_cr4,amd64_cr4_la57),&error_code);
		noir_svm_vmwrite8(vmcb,number_of_bytes_fetched,(u8)len);
	}
}

void static nvc_svm_decoder_instruction_handler(noir_gpr_state_p gpr_state,noir_svm_vcpu_p vcpu,noir_svm_custom_vcpu_p cvcpu)
{
	// This interception does not involve assisting decodings.
	// However, it still helps if Next-RIP Saving is unsupported.
	if(!noir_bt(&hvm_p->relative_hvm->virt_cap.capabilities,amd64_cpuid_nrips))
	{
		const void* vmcb=(cvcpu?cvcpu->vmcb:vcpu->vmcb).virt;
		u32 mode=0,len=0;
		u64 nrip;
		// Fetch the instruction.
		nvc_svm_fetch_instruction(vcpu,cvcpu);
		// Calculate the length.
		if(noir_svm_vmcb_bt32(vmcb,guest_cs_attrib,9))noir_bts(&mode,1);
		if(noir_svm_vmcb_bt32(vmcb,guest_cs_attrib,10))noir_bts(&mode,0);
		len=noir_get_instruction_length_ex((u8p)((ulong_ptr)vmcb+guest_instruction_bytes),mode);
		nrip=noir_svm_vmread64(vmcb,guest_rip)+len;
		if(noir_svm_vmcb_bt32(vmcb,guest_cs_attrib,9))nrip&=0xFFFFFFFF;
		noir_svm_vmwrite64(vmcb,next_rip,nrip);
	}
}

void static nvc_svm_decoder_event_handler(noir_gpr_state_p gpr_state,noir_svm_vcpu_p vcpu,noir_svm_custom_vcpu_p cvcpu)
{
	// This interception does not involve assisting decodings.
	// Event has no instruction length, so just do nothing.
}

void static nvc_svm_decoder_cr_access_handler(noir_gpr_state_p gpr_state,noir_svm_vcpu_p vcpu,noir_svm_custom_vcpu_p cvcpu)
{
	if(!noir_bt(&hvm_p->relative_hvm->virt_cap.capabilities,amd64_cpuid_decoder))
		nvd_printf("Control-Register Access decoder is not supported yet!\n");
}

void static nvc_svm_decoder_dr_access_handler(noir_gpr_state_p gpr_state,noir_svm_vcpu_p vcpu,noir_svm_custom_vcpu_p cvcpu)
{
	if(!noir_bt(&hvm_p->relative_hvm->virt_cap.capabilities,amd64_cpuid_decoder))
		nvd_printf("Debug-Register Access decoder is not supported yet!\n");
}

void static nvc_svm_decoder_pf_handler(noir_gpr_state_p gpr_state,noir_svm_vcpu_p vcpu,noir_svm_custom_vcpu_p cvcpu)
{
	// For #PF interceptions, fetching the instructions is just what we need to do.
	if(!noir_bt(&hvm_p->relative_hvm->virt_cap.capabilities,amd64_cpuid_decoder))
		nvc_svm_fetch_instruction(vcpu,cvcpu);
}

void static nvc_svm_decoder_int_handler(noir_gpr_state_p gpr_state,noir_svm_vcpu_p vcpu,noir_svm_custom_vcpu_p cvcpu)
{
	if(!noir_bt(&hvm_p->relative_hvm->virt_cap.capabilities,amd64_cpuid_decoder))
		nvd_printf("Software-Interrupt decoder is not supported yet!\n");
}

void static nvc_svm_decoder_invlpg_handler(noir_gpr_state_p gpr_state,noir_svm_vcpu_p vcpu,noir_svm_custom_vcpu_p cvcpu)
{
	if(!noir_bt(&hvm_p->relative_hvm->virt_cap.capabilities,amd64_cpuid_decoder))
		nvd_printf("The invlpg instruction decoder is not supported yet!\n");
}

void static nvc_svm_decoder_io_handler(noir_gpr_state_p gpr_state,noir_svm_vcpu_p vcpu,noir_svm_custom_vcpu_p cvcpu)
{
	// AMD-V will always assist decoding I/O instructions, regardless of the support to Decode-Assists!
	// The next rip is always saved in Exit-Info 2, regardless of the support to Next-Rip Saving!
	if(!noir_bt(&hvm_p->relative_hvm->virt_cap.capabilities,amd64_cpuid_nrips))
	{
		const void* vmcb=(cvcpu?cvcpu->vmcb:vcpu->vmcb).virt;
		noir_svm_vmwrite64(vmcb,next_rip,noir_svm_vmread64(vmcb,exit_info2));
	}
}

void static nvc_svm_decoder_npf_handler(noir_gpr_state_p gpr_state,noir_svm_vcpu_p vcpu,noir_svm_custom_vcpu_p cvcpu)
{
	const void* vmcb=(cvcpu?cvcpu->vmcb:vcpu->vmcb).virt;
	u64 gip=noir_svm_vmread64(vmcb,guest_rip);
	u64 gpa=noir_svm_vmread64(vmcb,exit_info2);
	nvd_printf("[Fetch - %s] rip=0x%p triggered #NPF! GPA=0x%llX\n",cvcpu?"CVM Guest":"Subv Host",gip,gpa);
	// For #NPF interceptions, fetching the instructions is just what we need to do.
	if(!noir_bt(&hvm_p->relative_hvm->virt_cap.capabilities,amd64_cpuid_decoder))
		nvc_svm_fetch_instruction(vcpu,cvcpu);
}