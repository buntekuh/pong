//
// Game v0
//

// include standard library for useful constants
.stdlib

.script
	def rgb555 r, g, b
		r = r * 31 / 255
		g = g * 31 / 255
		b = b * 31 / 255
		return	b + g * 32 + r * 1024
	end

	//say rgb555 0xff, 0xff, 0xff
.end

//.def MODE3 = 0x3
.def MODE4 = 0x4
.def BG2_ENABLE = (1 << 10)
// .def BG2_MODE3 = MODE3 | BG2_ENABLE

.def VRAM = 0x06000000
.def BG_PALETTE = 0x05000000
.def SCREEN_WIDTH = 240
.def HALF_SCREEN_WIDTH = 120
.def SCREEN_HEIGHT = 160

.def COLOR_BLUEGREEN = 12609
.def COLOR_WHITE = 32767
.def PALETTE_INDEX_ONE = (1 | 1 << 16)

.def PADDLE_WIDTH = 3
.def PADDLE_HEIGHT = 20

.struct Player = iwram
	.i8 paddle_y, score
.end

.struct AI = iwram
	.i8 paddle_y, score
.end

// GBA header
.begin header
	.arm
	b main
	.logo
	.title "Pong"
	.str "CUNE77"
	.i16 150, 0, 0, 0, 0
	.i8 0						// version
	.crc
	.i16 0
	b header				 	// ensure ROM isn't interpreted as multi-boot
	.str "SRAM_Vnnn" 			// tell emulators to reserve 32K of SRAM
	.align 4
.end


.begin main
	.arm
	// set cartridge wait state for faster access
	ldr r0, =REG_WAITCNT
	ldr r1, =0x4317
	strh r1, [r0]

	// Set display to Mode 4 with BG2 enabled, this is the gba pixel graphics mode
	ldr r0, =REG_DISPCNT
	//ldr r1, =BG2_MODE3
	ldr r1, =(MODE4 | BG2_ENABLE)
	strh r1, [r0]

	// Initialize color palette

	ldr r0, =0x05000000      // palette base
	ldr r1, =(COLOR_BLUEGREEN) // background color
	strh r1, [r0]            
	add r0, #2				
	ldr r1, =(COLOR_WHITE)		// foreground color
	strh r1, [r0]                      


	// initialize variables
	// put paddle at middle height
	ldr r0, =Player.paddle_y
	ldrb r1, =SCREEN_HEIGHT / 2
	strb r1, [r0]

	// set player score to 0
	ldr r0, =Player.score
	mov r1, #0
	strb r1, [r0]

	// initialize interrupts
    ldr r0, =irq_handler
    ldr r1, =0x03007FFC
    str r0, [r1]

 
	// Enable master interrupt flag
	ldr r0, =REG_IME
	mov r1, #1
	str r1, [r0]   // REG_IME = 0x4000208
		 				// store color
 		
	// Enable specific interrupts
	ldr r0, =REG_IE     // 0x4000200
	//ldr r1, =(IRQ_VBLANK | IRQ_TIMER0 | IRQ_KEYPAD)
	mov r1, #0x0001 // IRQ_VBLANK
	str r1, [r0]

	ldr r0, =REG_DISPSTAT   // 0x4000004
	mov r1, #(1 << 3)       // Bit 3 = VBlank IRQ enable
	str r1, [r0]

	// infinite loop
	loop:
		b loop

irq_handler:

	stmfd sp!, {lr} 						// push the link register on the stack before calling subroutines

	//bl fill_screen
	bl draw_paddle
	bl draw_center_line

	ldmfd sp!, {lr}							// pop the link register

	subs pc, lr, #4
	
	/*
	ldr r0, =Player.paddle_y
	ldrb r1, [r0]
	add r1, r1, #1
	strb r1, [r0]*/

	/*
		Some thoughts on how to set a flag, that says that we are still drawing and skip the drawing this time round

	ldr r0, =REG_IF
    ldr r1, [r0]
    tst r1, #IRQ_VBLANK
    beq skip

    // Frame counter
    ldr r2, =frame_counter
    ldr r3, [r2]
    add r3, r3, #1
    str r3, [r2]

    // Only draw on even frames
    tst r3, #1
    bne skip

    bl draw_frame

	skip:
		mov r1, #IRQ_VBLANK
		str r1, [r0]
		subs pc, lr, #4



	*/



/*
	Fill the screen with a background colour

	r0: location of screen in memory
	r1: color
	r2: counter
*/
fill_screen:
	
	ldr r0, =VRAM
	mov r1, #0
	mov r2, #0

	fill_screen_loop:
		strh r1, [r0]			 				// store color

		add r0, #2								
		add r2, #1								// increase counter
		cmp r2, #(SCREEN_WIDTH * (SCREEN_HEIGHT / 2))	// there are width x height pixel
		blt fill_screen_loop					// stop painting when this number is reached.
	bx lr


/*
	draw a line down the middle

	r0: pixel location to print
	r1: color
	r3: y counter
*/
draw_center_line:
	ldr r0, =VRAM			 					// base VRAM address
	mov r1, #(1 << 8)	 						// color
	mov r3, #0					 				// y-counter

	// calculate location of first pixel to draw
	add r0, #HALF_SCREEN_WIDTH					// base screen location and then we go halfway across the screen

	loop_middle_line:
		strh r1, [r0]							// paint pixel location
		add r0, #SCREEN_WIDTH				// calculate next paint position
		add r3, #1								// increase y counter
		cmp r3, #SCREEN_HEIGHT					// test if we reached the end
		blt loop_middle_line					// if not continue the loop

	bx lr

/*
	draw the paddle
	
	r0: base location of paddle on screen
	r1: Color
	r2: x counter
	r3: y counter
	r4: temporary value
	r5: Screen Width
*/
draw_paddle:
	ldr r0, =VRAM								// r0 VRAM points to the location the screen memory starts at
	ldr r1, = (1 | 1 << 8)		 				// color
	mov r3, #0							 		// y-counter
	ldr r5, =SCREEN_WIDTH						

	// calculate original draw location:
	// VRAM + Player.paddle_y * SCREEN_WIDTH + PADDLE_X
	ldr r4, =Player.paddle_y	 				// r4 store paddly_y memory location
	ldrb r4, [r4]								// r4 then load paddle_y value from there
	sub r4, #(PADDLE_HEIGHT/2)
	
	mul r4, r5									// r4 Player.paddle_y * SCREEN_WIDTH
	add r0, #PADDLE_WIDTH						// add the paddle x location
	add r0, r4									// add the two values together, r0 now contains the paddle base location

	loop_paddle_y:
		mov r2, #0								// reset the inner loop value

		loop_paddle_x:
			mul r4, r5, r3						// calculate the y progression and save it to r4
			add r4, r0 							// add the paddle base location
			add r4, r2							// then add the paddle base location and the x progression
			add r4, r2							// anything in the x direction is added twice
			strh r1, [r4]						// write color to pixel location. color is two bytes wide so we write a half word	
			
			add r2, #1							// increase the x counter
			cmp r2, #PADDLE_WIDTH				// and loop unless paddle width is reached
			blt loop_paddle_x					// if paddle width is reached, the line is as wide as the paddle and we progress to the next line underneath
			add r3, #1							// increase the x counter
			cmp r3, #PADDLE_HEIGHT				// and loop unless the paddle height is reached
			blt loop_paddle_y
	bx lr

	.pool
.end

