import random

def generate_final_ooo_test(filename="ooo_mem_test.s", total_goal=50000):
    r_type = ["add", "sub", "sll", "slt", "sltu", "xor", "srl", "sra", "or", "and"]
    m_type = ["mul", "mulh", "mulhsu", "mulhu", "div", "divu", "rem", "remu"]
    i_type = ["addi", "slti", "sltiu", "xori", "ori", "andi"]
    shifts_i = ["slli", "srli", "srai"]
    load_types = ["lw", "lhu", "lb"] 
    store_types = ["sw", "sh", "sb"]

    with open(filename, "w") as f:
        f.write(".section .text.init, \"ax\"\n")
        f.write(".global _start\n\n_start:\n")

        # FIX: Use the 'la' pseudo-op. 
        # The assembler expands this to a matched auipc/addi pair automatically.
        f.write("    la x1, data_space\n")

        for i in range(2, 32):
            f.write(f"    li x{i}, {random.randint(1, 100)}\n")

        inst_count = 0
        label_id = 0

        while inst_count < total_goal:
            mode = random.choice(["R_TYPE", "I_TYPE", "M_TYPE", "LOAD", "STORE"])
            
            rd = random.randint(2, 31)
            rs1 = random.randint(2, 31)
            rs2 = random.randint(2, 31)
            # Offset must be within the range of the data_space defined below
            safe_offset = random.randrange(0, 1024, 4) 

            if mode == "R_TYPE":
                f.write(f"    {random.choice(r_type)} x{rd}, x{rs1}, x{rs2}\n")
                inst_count += 1
            elif mode == "I_TYPE":
                op = random.choice(i_type + shifts_i)
                imm = random.randint(0, 31) if op in shifts_i else random.randint(-2048, 2047)
                f.write(f"    {op} x{rd}, x{rs1}, {imm}\n")
                inst_count += 1
            elif mode == "M_TYPE":
                f.write(f"    {random.choice(m_type)} x{rd}, x{rs1}, x{rs2}\n")
                inst_count += 1
            elif mode == "LOAD":
                f.write(f"    {random.choice(load_types)} x{rd}, {safe_offset}(x1)\n")
                inst_count += 1
            elif mode == "STORE":
                f.write(f"    {random.choice(store_types)} x{rd}, {safe_offset}(x1)\n")
                inst_count += 1

        f.write("\n# Termination Signal\n")
        f.write("    slti x0, x0, -256\n")

        # Explicitly placing data in a valid memory region
        f.write("\n.section .data\n")
        f.write(".align 4\ndata_space:\n")
        f.write("    .rept 1024\n") # 4KB of data space
        f.write("    .word 0x5555AAAA\n")
        f.write("    .endr\n")

    print(f"Generated {filename}")

if __name__ == "__main__":
    generate_final_ooo_test()