# Conway's Game of Life for RARS bitmap display (RISC-V)
# Поле 32x32, тороидальная топология. Отрисовка 1 пиксель = 1 клетка.
# Структура функций описана в AGENT.md.

    .globl main

# ------------------------------------------------------------
# Константы
# ------------------------------------------------------------
    .equ WIDTH, 32
    .equ HEIGHT, 32
    .equ GRID_SIZE, WIDTH*HEIGHT
    .equ BITMAP_BASE, 0x10008000
    .equ COLOR_ALIVE, 0x00FFFFFF
    .equ COLOR_DEAD, 0x00000000
    .equ MAX_CELLS, GRID_SIZE
    .equ MAX_FILENAME, 128
    .equ FILE_BUFFER_SIZE, 4096

    .equ SYSCALL_PRINT_INT, 1
    .equ SYSCALL_PRINT_STRING, 4
    .equ SYSCALL_READ_INT, 5
    .equ SYSCALL_READ_STRING, 8
    .equ SYSCALL_EXIT, 10
    .equ SYSCALL_SLEEP, 32

    # Файловые системные вызовы RARS
    .equ SYSCALL_OPEN, 1024     # a0=filename, a1=flags(0=read)
    .equ SYSCALL_READ, 63       # a0=fd, a1=buf, a2=len
    .equ SYSCALL_CLOSE, 57      # a0=fd

# ------------------------------------------------------------
# Данные
# ------------------------------------------------------------
    .data
prompt_menu:
    .asciz "Выберите режим:\n1) Ввод координат с консоли\n2) Загрузка из файла\n> "
prompt_mode_error:
    .asciz "Некорректный выбор, попробуйте снова.\n"
prompt_k:
    .asciz "Введите количество живых клеток (K): "
prompt_coord:
    .asciz "Введите координаты x y: "
prompt_file:
    .asciz "Введите имя файла: "
file_error:
    .asciz "Не удалось открыть файл, попробуйте снова или введите другое имя.\n"
file_parse_error:
    .asciz "Ошибка чтения файла. Проверьте формат.\n"
finish_extinct:
    .asciz "Вся жизнь исчезла. Завершение.\n"
loading_done:
    .asciz "Стартовая конфигурация загружена. Запуск симуляции...\n"

newline:
    .asciz "\n"
space:
    .asciz " "

curr_grid:
    .space GRID_SIZE            # текущее состояние (байты 0/1)
next_grid:
    .space GRID_SIZE            # следующее состояние
filename_buf:
    .space MAX_FILENAME
file_buffer:
    .space FILE_BUFFER_SIZE

# ------------------------------------------------------------
# main: точка входа
# ------------------------------------------------------------
    .text
main:
    addi sp, sp, -16
    sw ra, 12(sp)
    sw s0, 8(sp)        # s0 = указатель на текущий буфер
    sw s1, 4(sp)        # s1 = указатель на следующий буфер

    # инициализация указателей на буферы
    la s0, curr_grid
    la s1, next_grid

    # очистить оба буфера
    mv a0, s0
    jal clear_grid
    mv a0, s1
    jal clear_grid

mode_select:
    jal print_menu_and_read_mode   # a0 = 1 или 2
    mv t0, a0
    li t1, 1
    beq t0, t1, init_console
    li t1, 2
    beq t0, t1, init_file
    # неверный выбор
    la a0, prompt_mode_error
    li a7, SYSCALL_PRINT_STRING
    ecall
    j mode_select

init_console:
    mv a0, s0
    jal read_console_init          # заполнить curr_grid
    j start_sim

init_file:
file_retry:
    la a0, prompt_file
    li a7, SYSCALL_PRINT_STRING
    ecall

    la a0, filename_buf
    li a1, MAX_FILENAME
    li a7, SYSCALL_READ_STRING
    ecall

    mv a0, filename_buf
    mv a1, s0
    jal load_from_file
    bgez a0, start_sim             # успех -> a0 = загруженное K

    # ошибка
    la a0, file_error
    li a7, SYSCALL_PRINT_STRING
    ecall
    j file_retry

start_sim:
    # сообщение о старте
    la a0, loading_done
    li a7, SYSCALL_PRINT_STRING
    ecall

    # нарисовать начальное состояние
    mv a0, s0
    jal draw_grid

sim_loop:
    mv a0, s0
    mv a1, s1
    jal step_life          # a0 = alive_count_next

    mv t0, a0              # сохранить количество живых
    beqz t0, simulation_end

    # swap s0 и s1
    mv t1, s0
    mv s0, s1
    mv s1, t1

    # отрисовать новое состояние
    mv a0, s0
    jal draw_grid

    # задержка ~100 мс
    li a0, 100
    jal delay

    j sim_loop

simulation_end:
    la a0, finish_extinct
    li a7, SYSCALL_PRINT_STRING
    ecall

    li a7, SYSCALL_EXIT
    ecall

# ------------------------------------------------------------
# print_menu_and_read_mode -> a0 = 1 или 2
# ------------------------------------------------------------
print_menu_and_read_mode:
    addi sp, sp, -8
    sw ra, 4(sp)

    la a0, prompt_menu
    li a7, SYSCALL_PRINT_STRING
    ecall

    li a7, SYSCALL_READ_INT
    ecall                    # a0 = введенное число

    lw ra, 4(sp)
    addi sp, sp, 8
    ret

# ------------------------------------------------------------
# clear_grid(ptr)
# a0 - указатель на буфер GRID_SIZE байт
# ------------------------------------------------------------
clear_grid:
    addi sp, sp, -12
    sw ra, 8(sp)
    sw s2, 4(sp)

    mv s2, a0
    li t0, GRID_SIZE
    li t1, 0
clear_loop:
    beqz t0, clear_done
    sb t1, 0(s2)
    addi s2, s2, 1
    addi t0, t0, -1
    j clear_loop
clear_done:
    lw ra, 8(sp)
    lw s2, 4(sp)
    addi sp, sp, 12
    ret

# ------------------------------------------------------------
# set_cell_alive(ptr, x, y)
# a0=buf ptr, a1=x, a2=y
# ------------------------------------------------------------
set_cell_alive:
    addi sp, sp, -8
    sw ra, 4(sp)

    li t0, WIDTH
    blt a1, t0, sca_x_ok
    j sca_end
sca_x_ok:
    bltz a1, sca_end
    li t0, HEIGHT
    blt a2, t0, sca_y_ok
    j sca_end
sca_y_ok:
    bltz a2, sca_end
    # index = y*WIDTH + x
    li t0, WIDTH
    mul t1, a2, t0
    add t1, t1, a1
    add t1, t1, a0      # адрес ячейки
    li t2, 1
    sb t2, 0(t1)
sca_end:
    lw ra, 4(sp)
    addi sp, sp, 8
    ret

# ------------------------------------------------------------
# draw_grid(ptr)
# a0 = ptr на GRID_SIZE байт 0/1
# ------------------------------------------------------------
draw_grid:
    addi sp, sp, -16
    sw ra, 12(sp)
    sw s2, 8(sp)
    sw s3, 4(sp)

    mv s2, a0          # ptr
    li t0, 0           # index
    li t1, BITMAP_BASE
    li t2, GRID_SIZE

    li t3, COLOR_ALIVE
    li t4, COLOR_DEAD

draw_loop:
    beq t0, t2, draw_done
    lb t5, 0(s2)
    beqz t5, draw_dead
    sw t3, 0(t1)
    j draw_next

draw_dead:
    sw t4, 0(t1)

draw_next:
    addi s2, s2, 1
    addi t1, t1, 4
    addi t0, t0, 1
    j draw_loop

draw_done:
    lw ra, 12(sp)
    lw s2, 8(sp)
    lw s3, 4(sp)
    addi sp, sp, 16
    ret

# ------------------------------------------------------------
# count_neighbors_torus(curr_ptr, x, y) -> a0 = число соседей
# ------------------------------------------------------------
count_neighbors_torus:
    addi sp, sp, -16
    sw ra, 12(sp)
    sw s2, 8(sp)
    sw s3, 4(sp)

    mv s2, a0   # curr_ptr
    mv s3, a1   # x
    mv t6, a2   # y

    li t0, 0    # счетчик соседей

    # перебор dx, dy в {-1,0,1}, кроме (0,0)
    li t1, -1   # dy = -1 старт
outer_dy:
    blt t1, 2, dy_ok
    j cnt_done

dy_ok:
    li t2, -1   # dx = -1
inner_dx:
    blt t2, 2, dx_ok
    addi t1, t1, 1
    li t2, -1
    j outer_dy

dx_ok:
    beqz t1, skip_center_check
    beqz t2, skip_center_check
    j compute_neighbor
skip_center_check:
    # если dy=0 и dx=0 -> пропустить
    beqz t1, check_dx_zero
    j compute_neighbor
check_dx_zero:
    beqz t2, skip_neighbor

compute_neighbor:
    # nx = (x + dx + WIDTH) & 31
    add t3, s3, t2
    li t4, WIDTH
    add t3, t3, t4
    addi t3, t3, 0
    li t5, 31
    and t3, t3, t5
    # ny = (y + dy + HEIGHT) & 31
    add t4, t6, t1
    li t5, HEIGHT
    add t4, t4, t5
    li t5, 31
    and t4, t4, t5
    # addr = curr_ptr + (ny*WIDTH + nx)
    li t5, WIDTH
    mul t5, t4, t5
    add t5, t5, t3
    add t5, t5, s2
    lb t5, 0(t5)
    add t0, t0, t5

skip_neighbor:
    addi t2, t2, 1
    j inner_dx

cnt_done:
    mv a0, t0

    lw ra, 12(sp)
    lw s2, 8(sp)
    lw s3, 4(sp)
    addi sp, sp, 16
    ret

# ------------------------------------------------------------
# step_life(curr_ptr, next_ptr) -> a0 = alive_count_next
# ------------------------------------------------------------
step_life:
    addi sp, sp, -24
    sw ra, 20(sp)
    sw s2, 16(sp)
    sw s3, 12(sp)
    sw s4, 8(sp)
    sw s5, 4(sp)

    mv s2, a0      # curr
    mv s3, a1      # next

    li s4, 0       # y
    li t7, 0       # alive_count

step_row:
    li s5, 0       # x
step_col:
    # count neighbors
    mv a0, s2
    mv a1, s5
    mv a2, s4
    jal count_neighbors_torus   # a0 = neighbors

    mv t0, a0      # neighbors
    # current cell value
    li t1, WIDTH
    mul t2, s4, t1
    add t2, t2, s5
    add t2, t2, s2
    lb t3, 0(t2)   # current state

    # rules
    li t4, 0
    # birth: dead (0) with 3 neighbors
    beqz t3, check_birth
    # alive cell
    li t5, 2
    beq t0, t5, cell_survives
    li t5, 3
    beq t0, t5, cell_survives
    j cell_dies

check_birth:
    li t5, 3
    beq t0, t5, cell_becomes_alive
    j cell_dies

cell_survives:
    li t4, 1
    j store_next
cell_becomes_alive:
    li t4, 1
    j store_next
cell_dies:
    li t4, 0

store_next:
    # next_ptr[y*WIDTH + x] = t4
    li t5, WIDTH
    mul t6, s4, t5
    add t6, t6, s5
    add t6, t6, s3
    sb t4, 0(t6)

    add t7, t7, t4   # счет живых

    addi s5, s5, 1
    li t5, WIDTH
    blt s5, t5, step_col

    addi s4, s4, 1
    li t5, HEIGHT
    blt s4, t5, step_row

    mv a0, t7

    lw ra, 20(sp)
    lw s2, 16(sp)
    lw s3, 12(sp)
    lw s4, 8(sp)
    lw s5, 4(sp)
    addi sp, sp, 24
    ret

# ------------------------------------------------------------
# read_console_init(buf)
# a0 = ptr to curr_grid
# ------------------------------------------------------------
read_console_init:
    addi sp, sp, -16
    sw ra, 12(sp)
    sw s2, 8(sp)
    sw s3, 4(sp)

    mv s2, a0

    la a0, prompt_k
    li a7, SYSCALL_PRINT_STRING
    ecall

    li a7, SYSCALL_READ_INT
    ecall
    mv s3, a0          # K

    li t0, 0
read_coords_loop:
    beq t0, s3, rci_done
    la a0, prompt_coord
    li a7, SYSCALL_PRINT_STRING
    ecall

    li a7, SYSCALL_READ_INT
    ecall
    mv t1, a0          # x
    li a7, SYSCALL_READ_INT
    ecall
    mv t2, a0          # y

    mv a0, s2
    mv a1, t1
    mv a2, t2
    jal set_cell_alive

    addi t0, t0, 1
    j read_coords_loop

rci_done:
    lw ra, 12(sp)
    lw s2, 8(sp)
    lw s3, 4(sp)
    addi sp, sp, 16
    ret

# ------------------------------------------------------------
# delay(milliseconds)
# a0 = миллисекунды
# ------------------------------------------------------------
delay:
    addi sp, sp, -8
    sw ra, 4(sp)

    li a7, SYSCALL_SLEEP
    ecall

    lw ra, 4(sp)
    addi sp, sp, 8
    ret

# ------------------------------------------------------------
# read_string(buf, len) helper (обертка)
# ------------------------------------------------------------
read_string:
    addi sp, sp, -8
    sw ra, 4(sp)

    li a7, SYSCALL_READ_STRING
    ecall

    lw ra, 4(sp)
    addi sp, sp, 8
    ret

# ------------------------------------------------------------
# load_from_file(filename_ptr, curr_ptr) -> a0 = K_loaded или -1 при ошибке
# ------------------------------------------------------------
load_from_file:
    addi sp, sp, -24
    sw ra, 20(sp)
    sw s2, 16(sp)
    sw s3, 12(sp)
    sw s4, 8(sp)
    sw s5, 4(sp)

    mv s2, a0      # filename
    mv s3, a1      # curr_ptr

    # open file for read
    mv a0, s2
    li a1, 0       # flags: read-only
    li a7, SYSCALL_OPEN
    ecall
    bltz a0, lff_error
    mv s4, a0      # fd

    # read file into buffer
    mv a0, s4
    la a1, file_buffer
    li a2, FILE_BUFFER_SIZE
    li a7, SYSCALL_READ
    ecall
    bltz a0, lff_close_error
    mv s5, a0      # bytes_read

    # close
    mv a0, s4
    li a7, SYSCALL_CLOSE
    ecall

    # очистить целевой буфер
    mv a0, s3
    jal clear_grid

    # парсинг
    la t0, file_buffer      # ptr
    add t1, t0, s5          # end

    mv a0, t0
    mv a1, t1
    jal parse_next_int      # a0=value, a1=next_ptr, a2=error_flag
    bnez a2, lff_parse_error
    mv s5, a0               # K
    mv t0, a1               # ptr после числа

    li t2, MAX_CELLS
    ble s5, t2, lff_k_ok
    li s5, MAX_CELLS
lff_k_ok:
    li t3, 0                # count placed

lff_coord_loop:
    beq t3, s5, lff_success
    mv a0, t0
    mv a1, t1
    jal parse_next_int
    bnez a2, lff_success    # если числа закончились — завершить
    mv t4, a0               # x
    mv t0, a1

    mv a0, t0
    mv a1, t1
    jal parse_next_int
    bnez a2, lff_success
    mv t5, a0               # y
    mv t0, a1

    mv a0, s3
    mv a1, t4
    mv a2, t5
    jal set_cell_alive

    addi t3, t3, 1
    j lff_coord_loop

lff_success:
    mv a0, t3          # количество реально установленных
    lw ra, 20(sp)
    lw s2, 16(sp)
    lw s3, 12(sp)
    lw s4, 8(sp)
    lw s5, 4(sp)
    addi sp, sp, 24
    ret

lff_parse_error:
    la a0, file_parse_error
    li a7, SYSCALL_PRINT_STRING
    ecall

lff_close_error:
    # попытка закрыть, если fd валиден
    mv a0, s4
    li a7, SYSCALL_CLOSE
    ecall

lff_error:
    li a0, -1
    lw ra, 20(sp)
    lw s2, 16(sp)
    lw s3, 12(sp)
    lw s4, 8(sp)
    lw s5, 4(sp)
    addi sp, sp, 24
    ret

# ------------------------------------------------------------
# parse_next_int(ptr_start=a0, ptr_end=a1) -> a0=value, a1=next_ptr, a2=error_flag
# Считывает следующее неотрицательное число из буфера.
# ------------------------------------------------------------
parse_next_int:
    addi sp, sp, -12
    sw ra, 8(sp)
    sw s2, 4(sp)

    mv s2, a0   # ptr
    mv t1, a1   # end

    li t0, 0    # value
    li a2, 0    # error_flag

    # пропустить пробелы/переводы строк
pni_skip:
    beq s2, t1, pni_error
    lbu t2, 0(s2)
    li t3, ' '
    beq t2, t3, pni_advance
    li t3, '\n'
    beq t2, t3, pni_advance
    li t3, '\r'
    beq t2, t3, pni_advance
    li t3, '\t'
    beq t2, t3, pni_advance
    j pni_digits
pni_advance:
    addi s2, s2, 1
    j pni_skip

pni_digits:
    beq s2, t1, pni_error
    lbu t2, 0(s2)
    blt t2, '0', pni_finish_empty
    bgt t2, '9', pni_finish_empty
    # цифра
    addi t2, t2, -'0'
    li t3, 10
    mul t0, t0, t3
    add t0, t0, t2
    addi s2, s2, 1
    j pni_digits

pni_finish_empty:
    mv a0, t0
    mv a1, s2
    lw ra, 8(sp)
    lw s2, 4(sp)
    addi sp, sp, 12
    ret

pni_error:
    li a2, 1
    mv a0, zero
    mv a1, s2
    lw ra, 8(sp)
    lw s2, 4(sp)
    addi sp, sp, 12
    ret
