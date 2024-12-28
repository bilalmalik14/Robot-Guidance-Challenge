;*****************************************************************
;* Nishaa Badar, Bilal Malik. & Akaran Balasuresh
;*****************************************************************
              XDEF Entry, _Startup ;
              ABSENTRY Entry 
              INCLUDE "derivative.inc"

; LCD and addresses 
CLEAR_HOME    EQU   $01                   ; Clear the display and home the cursor
INTERFACE     EQU   $38                   ; 8 bit interface, two line display
CURSOR_OFF    EQU   $0C                   ; Display on, cursor off
SHIFT_OFF     EQU   $06                   ; Address increments, no character shift
LCD_SEC_LINE  EQU   64                    ; Starting addr. of 2nd line of LCD (note decimal value!)
LCD_CNTR      EQU   PTJ                   ; LCD Control Register: E = PJ7, RS = PJ6
LCD_DAT       EQU   PORTB                 ; LCD Data Register: D7 = PB7, ... , D0 = PB0
LCD_E         EQU   $80                   ; LCD E-signal pin
LCD_RS        EQU   $40                   ; LCD RS-signal pin
NULL          EQU   00                    ; Null 
CR            EQU   $0D                   ; Char-return
SPACE         EQU   ' '                   ; Space


;finite state machine states 
START         EQU   0
FWD           EQU   1                     
ALL_STOP      EQU   2                     
LEFT_TRN      EQU   3
RIGHT_TRN     EQU   4
REV_TRN       EQU   5                     
LEFT_ALIGN    EQU   6                     
RIGHT_ALIGN   EQU   7 


; timer for full left and right turns 
T_LEFT        EQU   8                           
T_RIGHT       EQU   8                             

; variable/data section
; ---------------------
              ORG   $3800
;*****************************************************************************
;Initial values determined from the initial measurements and Variance.       *
;*****************************************************************************
BASE_LINE     FCB   $9D                  ;Sensor Calibration: (Will change depending on EEBOT) 
BASE_BOW      FCB   $CA                  ;These values ($9D, $CA, $CA, $CC, $CC)
BASE_MID      FCB   $CA                  ;represent the baseline or initial readings for the sensors.
BASE_PORT     FCB   $CC
BASE_STBD     FCB   $CC
;*****************************************************************************
LINE_VARIANCE           FCB   $21           ; Adding variance based on testing to 
BOW_VARIANCE            FCB   $21           ; Sensor readings are compared to the baseline values:
PORT_VARIANCE           FCB   $21           ; with the added or subtracted variances.           
MID_VARIANCE            FCB   $20
STARBOARD_VARIANCE      FCB   $21



;*****************************************************************************
TOP_LINE      RMB   20                      ; Top line of the LCD display
              FCB   NULL                    ; terminated by null
              
BOT_LINE      RMB   20                      ; Bottom line of the LCD display
              FCB   NULL                    ; terminated by null

CLEAR_LINE    FCC   '                  '    ; Clear the line of display
              FCB   NULL                    ; terminated by null

TEMP          RMB   1                       ;The TEMP variable is used as a temporary location to store 
                                            ;the current state of the hardware port (PORTA)
                                            
                                            
;*******************************************************
;photoresistor sensor registers
;*******************************************************
SENSOR_LINE   FCB   $01                      
SENSOR_BOW    FCB   $23                     ;These storage locations are  used to hold initial sensor readings 
SENSOR_PORT   FCB   $45  
SENSOR_MID    FCB   $67                    ;or reference values for comparison in the subsequent sections of the code. 
SENSOR_STBD   FCB   $89                     ;The actual use of these values would depend on the context of the program,
                    ;and how these values are updated during the execution of the code.
SENSOR_NUM    RMB   1 



; Variable Section (Sourced from Lab 4 & 5)
;***************************************************************************************************
              ORG   $3850                   ; Where TOF counter register is located
TOF_COUNTER   dc.b  0                       ; The timer, incremented at 23Hz
CRNT_STATE    dc.b  2                       ; Current state Reg
T_TURN        ds.b  1                       ; time (Halt) turning
TEN_THOUS     ds.b  1                       ; 10,000 digit
THOUSANDS     ds.b  1                       ; 1,000 digit
HUNDREDS      ds.b  1                       ; 100 digit
TENS          ds.b  1                       ; 10 digit
UNITS         ds.b  1                       ; 1 digit
NO_BLANK      ds.b  1                       ; Blnk
HEX_TABLE     FCC   '0123456789ABCDEF'    ; Table for converting values
BCD_SPARE     RMB   2

; Code Section
;***************************************************************************************************
              ORG   $4000
Entry:                                                                       
_Startup: 

              LDS   #$4000                 ; Initialize the stack pointer
              CLI                          ; Enable interrupts
              JSR   INIT                   ; Initialize ports
              JSR   openADC                ; Initialize the ATD
              JSR   initLCD                ; Initialize the LCD
              JSR   CLR_LCD_BUF            ; Write characters to the LCD buffer 
              BSET  DDRA,%00000011         ; STAR_DIR, PORT_DIR                        
              BSET  DDRT,%00110000         ; STAR_SPEED, PORT_SPEED                    
              JSR   initAD                 ; Initialize ATD converter                  
              JSR   initLCD                ; Initialize the LCD                        
              JSR   clrLCD                 ; Clear LCD & home  
              LDX   #msg1                     ; Display msg1                              
              JSR   putsLCD                   ; ""                                        
                                                ;                                         
              LDAA  #$8A                      ; Move LCD cursor to the end of msg1        
              JSR   cmd2LCD                   ; ""                                        
              LDX   #msg2                     ; Display msg2                              
              JSR   putsLCD                   ; ""                                        
                                              ;                                           
              LDAA  #$C0                      ; Move LCD cursor to the 2nd row            
              JSR   cmd2LCD                   ; ""                                        
              LDX   #msg3                     ; Display msg3                              
              JSR   putsLCD                   ; ""                                      
                                            ;                                           
              LDAA  #$C7                      ; Move LCD cursor to the end of msg3        
              JSR   cmd2LCD                   ; ""                                        
              LDX   #msg4                     ; Display msg4                              
              JSR   putsLCD    
              JSR   ENABLE_TOF             ; Jump to TOF initialization

MAIN        
              JSR   G_LEDS_ON              ; Enable the guider LEDs   
              JSR   READ_SENSORS           ; Read the 5 guider sensors
              JSR   G_LEDS_OFF             ; Disable the guider LEDs                   
              JSR   UPDT_DISPL         
              LDAA  CRNT_STATE         
              JSR   DISPATCHER         
              BRA   MAIN               

; Data Section
;***************************************************************************************************
;********************************************************************************************
          msg1: dc.b  "St:",0                   ; Current state label
          msg2: dc.b  "R:",0                    ; Sensor readings label
          msg3: dc.b  "Vt:",0                   ;Battery voltage label
          msg4: dc.b  "B:",0                    ; Bumper status label
          
           tab: dc.b  "START  ",0               ; States
                dc.b  "FWD    ",0               ; ""
                dc.b  "REV    ",0               ; ""
                dc.b  "RT_TRN ",0               ; ""
                dc.b  "LT_TRN ",0               ; ""
                dc.b  "RevTrn ",0               ; ""
                dc.b  "STANDBY",0               ; ""  
                dc.b  "RTimed ",0  
                                                                                                             
; Subroutine Section (Sourced from Lab 5 + More functions)
;*********************************************************************************************************|    
DISPATCHER        JSR   VERIFY_START                        ; Start of the Dispatcher                     |
                  RTS                                                                                    
                                                                                                         ;D
VERIFY_START      CMPA  #START                              ; Verify if the robot's state is START        I
                  BNE   VERIFY_FORWARD                      ; If not, move to FORWARD state validation    S
                  JSR   START_ST                            ; Validate START state                        P
                  RTS                                                                                    ;A
                                                                                                         ;T
VERIFY_FORWARD    CMPA  #FWD                                ; Verify if the robot's state is FORWARD      C
                  BNE   VERIFY_STOP                         ; If not, move to ALL_STOP state validation   H
                  JSR   FWD_ST                              ; Validate FORWARD state                      E
                  RTS                                                                                    ;R
                                                                                                         ;|
VERIFY_REV_TRN    CMPA  #REV_TRN                            ; Verify if the robot's state is REV_TURN     |
                  BNE   VERIFY_LEFT_ALIGN                   ; If not, move to LEFT_ALIGN state validation |
                  JSR   REV_TRN_ST                          ; Validate REV_TURN state                     |
                  RTS                                                                                   ; |
                                                                                                        ; |
VERIFY_STOP       CMPA  #ALL_STOP                           ; Verify if the robot's state is ALL_STOP     |
                  BNE   VERIFY_LEFT_TRN                     ; If not, move to LEFT_TURN state validation  |
                  JSR   ALL_STOP_ST                         ; Validate ALL_STOP state                     |
                  RTS                                                                                   ; |
                                                                                                        ; |
VERIFY_LEFT_TRN   CMPA  #LEFT_TRN                           ; Verify if the robot's state is LEFT_TURN    |
                  BNE   VERIFY_RIGHT_TRN                    ; If not, move to RIGHT_TURN state validation |
                  JSR   LEFT                                ; Validate LEFT_TURN state                    | 
                  RTS                                                                                   ; |                                  
                                                                                                        ; |
VERIFY_LEFT_ALIGN CMPA  #LEFT_ALIGN                         ; Verify if the robot's state is LEFT_ALIGN   |
                  BNE   VERIFY_RIGHT_ALIGN                  ; If not, move to RIGHT_ALIGN state validation|
                  JSR   LEFT_ALIGN_DONE                     ; Validate LEFT_ALIGN state                   |
                  RTS                                                                                   ; |
                                                                                                        ; |
VERIFY_RIGHT_TRN  CMPA  #RIGHT_TRN                          ; Verify if the robot's state is RIGHT_TURN   |
                  BNE   VERIFY_REV_TRN                      ; If not, move to REV_TURN state validation   |
                  JSR   RIGHT                               ; Validate RIGHT_TURN state                   |                    
                                                                                                        ; |
VERIFY_RIGHT_ALIGN CMPA  #RIGHT_ALIGN                       ; Verify if the robot's state is RIGHT_ALIGN  |
                  JSR   RIGHT_ALIGN_DONE                    ; Validate RIGHT_ALIGN state                  |
                  RTS                                       ; INVALID state                               |
                                                                                                        ; |
;*********************************************************************************************************
;Start State Function (If met, JSR to INIT_FWD, then end Sub)                                            *                                              |
;*********************************************************************************************************
START_ST          BRCLR   PORTAD0, %00000100,RELEASE                                    
                  JSR     INIT_FWD                                                               
                  MOVB    #FWD, CRNT_STATE

RELEASE           RTS                                                                                                                                  

;*********************************************************************************************************

FWD_ST            BRSET   PORTAD0, $04, NO_FWD_BUMP           ; Checks if the Front bumper is hit                           
                  MOVB    #REV_TRN, CRNT_STATE                ; if true, The state will change to REV_TURN                                
                                                                                           
                  JSR     UPDT_DISPL                          ; Update the display                                
                  JSR     INIT_REV                                                                
                  LDY     #12000                                                                   
                  JSR     del_50us                                                                
                  JSR     INIT_RIGHT                                                              
                  LDY     #6000                                                                   
                  JSR     del_50us                                                             
                  LBRA    EXIT                                                                    

NO_FWD_BUMP       BRSET   PORTAD0, $04, NO_FWD_REAR_BUMP      ; Checks if the Rear bumper is hit
                  MOVB    #ALL_STOP, CRNT_STATE               ; if true, The state will Change to the                    
                  JSR     INIT_STOP                           ; ALL_STOP state (Means Halt)
                  LBRA    EXIT 
                  
NO_FWD_REAR_BUMP  LDAA    SENSOR_BOW                                                              
                  ADDA    BOW_VARIANCE                                                               
                  CMPA    BASE_BOW                                                                
                  BPL     NOT_ALIGNED                                                                
                  LDAA    SENSOR_MID                                                              
                  ADDA    MID_VARIANCE                                                                
                  CMPA    BASE_MID                                                                
                  BPL     NOT_ALIGNED                                                               
                  LDAA    SENSOR_LINE                                                             
                  ADDA    LINE_VARIANCE                                                                
                  CMPA    BASE_LINE                                                               
                  BPL     CHECK_RIGHT_ALIGN                                                          
                  LDAA    SENSOR_LINE          ;thresholds are dynamically determined based on the initial readings                                                    
                  SUBA    LINE_VARIANCE        ;and variances defined in the data section of the program. If the actual                                                     
                  CMPA    BASE_LINE            ;sensor readings deviate from these thresholds (baseline +/- variance),                                                     
                  BMI     CHECK_LEFT_ALIGN     ;the program takes specific actions, such as initiating turns or stopping the robot.

;***************************************************************************************************                                                                  

NOT_ALIGNED       LDAA    SENSOR_PORT        ;Determines the movement of the Robot depending on the Sensors                                                    
                  ADDA    PORT_VARIANCE                                                               
                  CMPA    BASE_PORT                                                              
                  BPL     PARTIAL_LEFT_TRN    ;If the result is greater than or equal to BASE_PORT, branch to PARTIAL_LEFT_TRN.                                                     
                  BMI     NO_PORT             ;This  means that the sensor reading indicates an alignment condition that requires a partial left turn.                                               
                                              ;If the result is less than BASE_PORT, branch to NO_PORT. This likely means that the sensor reading does not indicate an alignment condition.
NO_PORT           LDAA    SENSOR_BOW                                                            
                  ADDA    BOW_VARIANCE                                                                 
                  CMPA    BASE_BOW                                                                
                  BPL     EXIT                                                                    
                  BMI     NO_BOW                                                              

NO_BOW            LDAA    SENSOR_STBD                                                             
                  ADDA    STARBOARD_VARIANCE                                                               
                  CMPA    BASE_STBD                                                               
                  BPL     PARTIAL_RIGHT_TRN                                                         
                  BMI     EXIT                 ;If certain conditions are met, The bot determines whether a partial left turn, a partial right turn, or no turn is needed.

;***************************************************************************************************

PARTIAL_LEFT_TRN  LDY     #6000                  ; The Robot's behavior related to left turns and left alignment.                                             
                  jsr     del_50us                                                                
                  JSR     INIT_LEFT                                                               
                  MOVB    #LEFT_TRN, CRNT_STATE                                                  
                  LDY     #6000                     ;The delays (6000 iterations of del_50us) introduced to control the duration of actions / to finish an action                                                 
                  JSR     del_50us                                                                
                  BRA     EXIT                                                                    

CHECK_LEFT_ALIGN  JSR     INIT_LEFT                                                               
                  MOVB    #LEFT_ALIGN, CRNT_STATE                                                 
                  BRA     EXIT

;*************************************************************************************************** 

PARTIAL_RIGHT_TRN LDY     #6000                                                                  
                  jsr     del_50us                      ; The Robot's behavior related to Right turns and right alignment                                          
                  JSR     INIT_RIGHT                                                              
                  MOVB    #RIGHT_TRN, CRNT_STATE        ;The delays (6000 iterations of del_50us) introduced to control the duration of actions / to finish an action                                         
                  LDY     #6000                                                                   
                  JSR     del_50us                                                                
                  BRA     EXIT                                                                   

CHECK_RIGHT_ALIGN JSR     INIT_RIGHT                                                              
                  MOVB    #RIGHT_ALIGN, CRNT_STATE                                                
                  BRA     EXIT                                                                                                                                                         

EXIT              RTS 

;***************************************************************************************************                                                                            
                                        ;For this Section:
LEFT              LDAA    SENSOR_BOW    ;the logic for left and right turns based on sensor readings. If the conditions for left or right alignment are met,                                                       
                  ADDA    BOW_VARIANCE  ;it sets the robot's state to forward (FWD) and initializes forward movtemen                                                                 
                  CMPA    BASE_BOW                                                               
                  BPL     LEFT_ALIGN_DONE                                                        
                  BMI     EXIT

LEFT_ALIGN_DONE   MOVB    #FWD, CRNT_STATE                                                        
                  JSR     INIT_FWD                                                                
                  BRA     EXIT                                                                    

RIGHT             LDAA    SENSOR_BOW                                                              
                  ADDA    BOW_VARIANCE                                                                
                  CMPA    BASE_BOW                                                                
                  BPL     RIGHT_ALIGN_DONE                                                        
                  BMI     EXIT 

RIGHT_ALIGN_DONE  MOVB    #FWD, CRNT_STATE                                                        
                  JSR     INIT_FWD                                                                
                  BRA     EXIT                                                                    

;***************************************************************************************************
                                        ;For this Section:
REV_TRN_ST        LDAA    SENSOR_BOW    ;In summary, REV_TRN_ST appears to handle the logic for reverse turning based on sensor readings,                                                           
                  ADDA    BOW_VARIANCE  ;and ALL_STOP_ST handles the condition for transitioning to the START state.                                                               
                  CMPA    BASE_BOW      ;The specific behavior depends on the actual sensor readings, variances, baselines, and the condition checked against PORTAD0                                                         
                  BMI     EXIT                                                                    
                  JSR     INIT_LEFT                                                               
                  MOVB    #FWD, CRNT_STATE                                                        
                  JSR     INIT_FWD                                                                
                  BRA     EXIT                                                                    

ALL_STOP_ST       BRSET   PORTAD0, %00000100, NO_START_BUMP                                       
                  MOVB    #START, CRNT_STATE                                                      

NO_START_BUMP     RTS                                                                             

; Initialization Subroutines
;***************************************************************************************************
INIT_RIGHT        BSET    PORTA,%00000010          
                  BCLR    PORTA,%00000001        
                  LDAA    TOF_COUNTER               ; Mark the Time for a forward turn.
                  ADDA    #T_RIGHT
                  STAA    T_TURN
                  RTS

INIT_LEFT        
                  BSET    PORTA,%00000001         
                  BCLR    PORTA,%00000010 
          
                  LDAA    TOF_COUNTER               ; Mark TOF time ("Time of Flight/distance")
                  ADDA    #T_LEFT                   ; Add left turn
                  STAA    T_TURN                    
                  RTS

INIT_FWD          BCLR    PORTA, %00000011          ; Set Forward Drive for both motors
                  BSET    PTT, %00110000            ; Turn on the drive motors
                  LDY    #100 ;EDIT
                  JSR     del_50us  ;EDIT   
                  RTS 

INIT_REV          BSET    PORTA,%00000011            ; Set Reverse Direction for both motors
                  BSET    PTT,%00110000              ; Turn on the drive motors
                  RTS

INIT_STOP         BCLR    PTT, %00110000            ; Turn off the drive motors
                  RTS


;***************************************************************************************************
;       Initialize Sensors
INIT              BCLR   DDRAD,$FF ;PORTAD(input)  (DDRAD @ $0272)
                  BSET   DDRA,$FF  ;PORTA (output) (DDRA @ $0002)
                  BSET   DDRB,$FF  ;PORTB (output) (DDRB @ $0003)
                  BSET   DDRJ,$C0  ;Pins 7,6 of PTJ (outputs) (DDRJ @ $026A)
                  RTS


;***************************************************************************************************
;        Initialize ADC              
openADC           MOVB   #$80,ATDCTL2 ; Turn on ADC (ATDCTL2 @ $0082)
                  LDY    #1           ; Wait for 50 us for ADC to be ready
                  JSR    del_50us     ; - " -
                  MOVB   #$20,ATDCTL3 ; 4 conversions on channel AN1 (ATDCTL3 @ $0083)
                  MOVB   #$97,ATDCTL4 ; 8-bit resolution, prescaler=48 (ATDCTL4 @ $0084)
                  RTS

;********************************************************************************
;*                          Clear LCD Buffer                                    *
;********************************************************************************
; This routine writes characters (ascii 20) into the LCD display
; buffer in order to prepare it for the building of a new display buffer.
; Done only once.
CLR_LCD_BUF       LDX   #CLEAR_LINE
                  LDY   #TOP_LINE
                  JSR   STRCPY

CLB_SECOND        LDX   #CLEAR_LINE
                  LDY   #BOT_LINE
                  JSR   STRCPY

CLB_EXIT          RTS

;*********************************************************************************      
; String Copy
; Copies a null-terminated string (including the null) from one location to another.
; X = starting address of null-terminated string
; Y =  first address of destination
STRCPY            PSHX            ; Protect the registers used
                  PSHY
                  PSHA

STRCPY_LOOP       LDAA 0,X        ; Get a source character
                  STAA 0,Y        ; Copy it to the destination
                  BEQ STRCPY_EXIT ; If it was the null, then exit
                  INX             ; Else increment the pointers
                  INY
                  BRA STRCPY_LOOP ; Repeat steps again in a loop

STRCPY_EXIT       PULA            ; Restore the registers
                  PULY
                  PULX
                  RTS  

;* **************************************************************************************************      
;*                                   Guider LEDs ON                                                 |
;* This routine enables the guider LEDs such that the sensor correspond to the lights.              |
;* Passed: Nothing (For both ON and OFF)                                                            |
;* Returns:Nothing (For both ON and OFF)                                                            |
;* Side: PORTA bit 5 is changed                                                                     |
G_LEDS_ON         BSET PORTA,%00100000 ; Set bit 5                                                  |
                  RTS                                                                             ; |
;*--------------------------------------------------------------------------------------------------*      
;*                                  Guider LEDs OFF                                                 |
;* This routine disables the guider LEDs. Readings of the sensor correspond to the ambient lighting |
;* Side: PORTA bit 5 is changed                                                                     |
;*                                                                                                  |
G_LEDS_OFF        BCLR PORTA,%00100000 ; Clear bit 5                                                |
                  RTS                  ;                                                            |    
; ***************************************************************************************************          
; *                             Reading Sensors Section                                             *
; ***************************************************************************************************  
READ_SENSORS      CLR   SENSOR_NUM     ; Select sensor number 0
                  LDX   #SENSOR_LINE   ; Point at the start of the sensor array

RS_MAIN_LOOP      LDAA  SENSOR_NUM     ; Select the correct sensor input
                  JSR   SELECT_SENSOR  ; on the hardware
                  LDY   #400           ; 20 ms delay to allow the
                  JSR   del_50us       ; sensor to stabilize
                  LDAA  #%10000001     ; Start A/D conversion on AN1
                  STAA  ATDCTL5
                  BRCLR ATDSTAT0,$80,* ; Repeat until A/D signals done
                  LDAA  ATDDR0L        ; A/D conversion is complete in ATDDR0L
                  STAA  0,X            ; so copy it to the sensor register
                  CPX   #SENSOR_STBD   ; If this is the last reading
                  BEQ   RS_EXIT        ; Then exit
                  INC   SENSOR_NUM     ; Else, increment the sensor number
                  INX                  ; and the pointer into the sensor array
                  BRA   RS_MAIN_LOOP   ; and do it again

RS_EXIT           RTS


; *************************************************************************************************     
; *                             Select Sensor                                                     *
; *************************************************************************************************      
SELECT_SENSOR     PSHA                ; Save the sensor number for the moment
                  LDAA PORTA          ; Clear the sensor selection bits to zeros
                  ANDA #%11100011
                  STAA TEMP           ; and save it into TEMP
                  PULA                ; Get the sensor number
                  ASLA                ; Shift the selection number left, twice
                  ASLA 
                  ANDA #%00011100     ; Clear irrelevant bit positions
                  ORAA TEMP           ; OR it into the sensor bit positions
                  STAA PORTA          ; Update the hardware
                  RTS


; *************************************************************************************************         
; *                             Display Sensors                                                   *
; *************************************************************************************************    
DP_FRONT_SENSOR   EQU TOP_LINE+3     ;Represents the position in the display buffer 
DP_PORT_SENSOR    EQU BOT_LINE+0     ;Represents the position in the display buffer 
DP_MID_SENSOR     EQU BOT_LINE+3     ;Represents the position in the display buffer 
DP_STBD_SENSOR    EQU BOT_LINE+6     ;Represents the position in the display buffer 
DP_LINE_SENSOR    EQU BOT_LINE+9     ;Represents the position in the display buffer 

DISPLAY_SENSORS   LDAA  SENSOR_BOW        ; Get the FRONT sensor value
                  JSR   BIN2ASC           ; Convert to ascii string in D
                  LDX   #DP_FRONT_SENSOR  ; Point to the LCD buffer position
                  STD   0,X               ; and write the 2 ascii digits there
                  LDAA  SENSOR_PORT       ; Repeat for the PORT value
                  JSR   BIN2ASC
                  LDX   #DP_PORT_SENSOR
                  STD   0,X
                  LDAA  SENSOR_MID        ; Repeat for the MID value
                  JSR   BIN2ASC
                  LDX   #DP_MID_SENSOR
                  STD   0,X
                  LDAA  SENSOR_STBD       ; Repeat for the STARBOARD value
                  JSR   BIN2ASC
                  LDX   #DP_STBD_SENSOR
                  STD   0,X
                  LDAA  SENSOR_LINE       ; Repeat for the LINE value
                  JSR   BIN2ASC
                  LDX   #DP_LINE_SENSOR
                  STD   0,X
                  LDAA  #CLEAR_HOME       ; Clear the display and home the cursor
                  JSR   cmd2LCD           ; ""
                  LDY   #40               ; Wait 2 ms until "clear display" command is complete
                  JSR   del_50us
                  LDX   #TOP_LINE         ; Now copy the buffer top line to the LCD
                  JSR   putsLCD
                  LDAA  #LCD_SEC_LINE     ; Position the LCD cursor on the second line
                  JSR   LCD_POS_CRSR
                  LDX   #BOT_LINE         ; Copy the buffer bottom line to the LCD
                  JSR   putsLCD
                  RTS
;********************************************************************************************
;*                              Sourced from Lab 1,2,3,4, 5                                 *
;********************************************************************************************
;* Update Display (Current State + Bumper Switches + Battery Voltage + Sensor Readings)     *
;********************************************************************************************
UPDT_DISPL      LDAA  #$82                      ; Move LCD cursor to the end of msg1
                JSR   cmd2LCD                   ;
                
                LDAB  CRNT_STATE                ; Display current state
                LSLB                            ; "
                LSLB                            ; "
                LSLB                            ; "
                LDX   #tab                      ; "
                ABX                             ; "
                JSR   putsLCD                   ; "
;*******************************************************************************************               
                LDAA  #$8F                      ; Move LCD cursor to the end of msg2
                JSR   cmd2LCD                   ; ""
                LDAA  SENSOR_BOW                ; Convert value from SENSOR_BOW to a
                JSR   BIN2ASC                   ; Two digit hexidecimal value
                JSR   putcLCD                   ; ""
                EXG   A,B                       ; ""
                JSR   putcLCD                   ; ""

                LDAA  #$92                      ; Move LCD cursor to Line position 
                JSR   cmd2LCD                   ; ""
                LDAA  SENSOR_LINE               ; Convert value from SENSOR_BOW to a
                JSR   BIN2ASC                   ; Two digit hexidecimal value
                JSR   putcLCD                   ; ""
                EXG   A,B                       ; ""
                JSR   putcLCD                   ; ""

                LDAA  #$CC                      ; Move LCD cursor to Port position on 2nd row 
                JSR   cmd2LCD                   ; ""
                LDAA  SENSOR_PORT               ; Convert value from SENSOR_BOW to a
                JSR   BIN2ASC                   ; Two digit hexidecimal value
                JSR   putcLCD                   ; ""
                EXG   A,B                       ; ""
                JSR   putcLCD                   ; ""

                LDAA  #$CF                      ; Move LCD cursor to Mid position on 2nd row 
                JSR   cmd2LCD                   ; ""
                LDAA  SENSOR_MID                ; Convert value from SENSOR_BOW to a
                JSR   BIN2ASC                   ; Two digit hexidecimal value
                JSR   putcLCD                   ; ""
                EXG   A,B                       ; ""
                JSR   putcLCD                   ; ""

                LDAA  #$D2                      ; Move LCD cursor to Starboard position on 2nd row 
                JSR   cmd2LCD                   ; ""
                LDAA  SENSOR_STBD               ; Convert value from SENSOR_BOW to a
                JSR   BIN2ASC                   ; Two digit hexidecimal value
                JSR   putcLCD                   ; ""
                EXG   A,B                       ; ""
                JSR   putcLCD                   ; ""
;********************************************************************************************          
                MOVB  #$90,ATDCTL5              ; Uns., sing. conv., mult., ch=0, start
                BRCLR ATDSTAT0,$80,*            ; Wait until the conver. seq. is complete
                LDAA  ATDDR0L                   ; Load the ch0 result - battery volt - into A
                LDAB  #39                       ; AccB = 39
                MUL                             ; AccD = 1st result x 39
                ADDD  #600                      ; AccD = 1st result x 39 + 600
                JSR   int2BCD
                JSR   BCD2ASC
                LDAA  #$C2                      ; move LCD cursor to the end of msg3
                JSR   cmd2LCD                   ; "                
                LDAA  TEN_THOUS                 ; output the TEN_THOUS ASCII character
                JSR   putcLCD                   ; "
                LDAA  THOUSANDS                 ; output the THOUSANDS ASCII character
                JSR   putcLCD                   ; "
                LDAA  #$2E                      ; output the HUNDREDS ASCII character
                JSR   putcLCD                   ; "
                LDAA  HUNDREDS                  ; output the HUNDREDS ASCII character
                JSR   putcLCD                   ; "                
;********************************************************************************************
                LDAA  #$C9                      ; Move LCD cursor to the end of msg4
                JSR   cmd2LCD
                
                BRCLR PORTAD0,#%00000100,bowON  ; If FWD_BUMP, then
                LDAA  #$20                      ;
                JSR   putcLCD                   ;
                BRA   stern_bump                ; Display 'B' on LCD (Bumper state)
         bowON: LDAA  #$42                      ; ""
                JSR   putcLCD                   ; ""
          
    stern_bump: BRCLR PORTAD0,#%00001000,sternON; If REV_BUMP, then
                LDAA  #$20                      ;
                JSR   putcLCD                   ;
                BRA   UPDT_DISPL_EXIT           ; Display 'S' on LCD
       sternON: LDAA  #$53                      ; ""
                JSR   putcLCD                   ; ""
UPDT_DISPL_EXIT RTS                             ; and exit
                
;***************************************************************************************************
;***************************************************************************************************
ENABLE_TOF        LDAA    #%10000000
                  STAA    TSCR1           ; Enable TCNT
                  STAA    TFLG2           ; Clear TOF
                  LDAA    #%10000100      ; Enable TOI and select prescale factor equal to 16
                  STAA    TSCR2
                  RTS

TOF_ISR           INC     TOF_COUNTER
                  LDAA    #%10000000      ; Clear
                  STAA    TFLG2           ; TOF
                  RTI


; Subroutines for Utilities (LCD + Delay + Integer to Binanry etc.)
;***************************************************************************************************
initLCD:          BSET    DDRB,%11111111  ; configure pins PS7,PS6,PS5,PS4 for output
                  BSET    DDRJ,%11000000  ; configure pins PE7,PE4 for output
                  LDY     #2000
                  JSR     del_50us
                  LDAA    #$28
                  JSR     cmd2LCD
                  LDAA    #$0C
                  JSR     cmd2LCD
                  LDAA    #$06
                  JSR     cmd2LCD
                  RTS
;***************************************************************************************************
;from guider
cmd2LCD:          BCLR  LCD_CNTR, LCD_RS ; select the LCD instruction
                  JSR   dataMov          ; send data to IR
                  RTS

;***************************************************************************************************
;FROM GUIDER
putsLCD:          LDAA  1,X+             ; get one character from  string
                  BEQ   donePS           ; get NULL character
                  JSR   putcLCD
                  BRA   putsLCD

donePS            RTS

;***************************************************************************************************
;not from guider


clrLCD:           LDAA  #$01
                  JSR   cmd2LCD
                  LDY   #40
                  JSR   del_50us
                  RTS

;***************************************************************************************************
;from guider and prev lab
del_50us          PSHX                   ; (2 E-clk) Protect the X register
eloop             LDX   #300             ; (2 E-clk) Initialize the inner loop counter
iloop             NOP                    ; (1 E-clk) No operation
                  DBNE X,iloop           ; (3 E-clk) If the inner cntr not 0, loop again
                  DBNE Y,eloop           ; (3 E-clk) If the outer cntr not 0, loop again
                  PULX                   ; (3 E-clk) Restore the X register
                  RTS                    ; (5 E-clk) Else return


;***************************************************************************************************
; from guider and prev lab 
putcLCD:          BSET  LCD_CNTR, LCD_RS  ; select the LCD data register (DR)c
                  JSR   dataMov           ; send data to DR
                  RTS

;***************************************************************************************************
; from guider and also prev lab
dataMov:          BSET  LCD_CNTR, LCD_E   ; pull LCD E-signal high
                  STAA  LCD_DAT           ; send the upper 4 bits of data to LCD
                  BCLR  LCD_CNTR, LCD_E   ; pull the LCD E-signal low to complete write oper.
                  LSLA                    ; match the lower 4 bits with LCD data pins
                  LSLA                    ; ""
                  LSLA                    ; ""
                  LSLA                    ; ""
                  BSET  LCD_CNTR, LCD_E   ; pull LCD E-signal high
                  STAA  LCD_DAT           ; send the lower 4 bits of data to LCD
                  BCLR  LCD_CNTR, LCD_E   ; pull the LCD E-signal low to complete write oper.
                  LDY   #1                ; adding this delay allows
                  JSR   del_50us          ; completion of most instructions
                  RTS

;***************************************************************************************************
; not from guider, from some other lab 
initAD            MOVB  #$C0,ATDCTL2      ;power up AD, select fast flag clear
                  JSR   del_50us          ;wait for 50 us
                  MOVB  #$00,ATDCTL3      ;8 conversions in a sequence
                  MOVB  #$85,ATDCTL4      ;res=8, conv-clks=2, prescal=12
                  BSET  ATDDIEN,$0C       ;configure pins AN03,AN02 as digital inputs
                  RTS

;***************************************************************************************************
; not from guider, from sone other lab
int2BCD           XGDX                    ;Save the binary number into .X
                  LDAA #0                 ;Clear the BCD_BUFFER
                  STAA TEN_THOUS
                  STAA THOUSANDS
                  STAA HUNDREDS
                  STAA TENS
                  STAA UNITS
                  STAA BCD_SPARE
                  STAA BCD_SPARE+1
                  CPX #0                  ; Check for a zero input
                  BEQ CON_EXIT            ; and if so, exit
                  XGDX                    ; Not zero, get the binary number back to .D as dividend
                  LDX #10                 ; Setup 10 (Decimal!) as the divisor
                  IDIV                    ; Divide Quotient is now in .X, remainder in .D
                  STAB UNITS              ; Store remainder
                  CPX #0                  ; If quotient is zero,
                  BEQ CON_EXIT            ; then exit
                  XGDX                    ; else swap first quotient back into .D
                  LDX #10                 ; and setup for another divide by 10
                  IDIV
                  STAB TENS
                  CPX #0
                  BEQ CON_EXIT
                  XGDX                    ; Swap quotient back into .D
                  LDX #10                 ; and setup for another divide by 10
                  IDIV
                  STAB HUNDREDS
                  CPX #0
                  BEQ CON_EXIT
                  XGDX                    ; Swap quotient back into .D
                  LDX #10                 ; and setup for another divide by 10
                  IDIV
                  STAB THOUSANDS
                  CPX #0
                  BEQ CON_EXIT
                  XGDX                    ; Swap quotient back into .D
                  LDX #10                 ; and setup for another divide by 10
                  IDIV
                  STAB TEN_THOUS

CON_EXIT          RTS                     ; Were done the conversion

LCD_POS_CRSR      ORAA #%10000000         ; Set the high bit of the control word
                  JSR cmd2LCD             ; and set the cursor address
                  RTS

;************************* converts a 4-bit binary number into its ASCII representation********************************************

;from guider 
BIN2ASC               PSHA               ; Save a copy of the input number
                      TAB            
                      ANDB #%00001111     ; Strip off the upper nibble
                      CLRA                ; D now contains 000n where n is the Lower nibble. Clear accumulator A.
                      ADDD #HEX_TABLE     ; Set up for indexed load
                      XGDX                
                      LDAA 0,X            ; Get the Lower nibble character
                      PULB                ; Retrieve the input number into ACCB
                      PSHA                ; and push the Lower nibble character in its place
                      RORB                ; Move the upper nibble of the input number
                      RORB                ; into the lower nibble position.
                      RORB
                      RORB 
                      ANDB #%00001111     ; Strip off the upper nibble
                      CLRA                ; D now contains 000n where n is the Upper Snibble 
                      ADDD #HEX_TABLE     ; Set up for indexed load
                      XGDX                                                               
                      LDAA 0,X            ; Get the Upper Snibble character into ACCA
                      PULB                ; Retrieve the Lower Snibble character into ACCB
                      RTS
;***************************************************************************************************
;***************************************************************************************************

; not from guider
;(Sourced from Lab 5- Eebot Guidance System)
;Integer to BCD   (Sourced from Lab 5- Eebot Guidance System)
;* 16-bit binary number in register .D --> BCD digits stored --> BCD_BUFFER.
;* Using IDIV (Integer Division) instruction provided by the HCS12, decimal digits are calcualyed by  dividing the binary number by ten.
;* The remainder from each division operation --> a decimal digit --> shifting the decimal number rightward one position at a time through divisions.
;* The remainder is a decimal digit within the range of 0 to 9 since we divided it by 10. 
;Quotient reaches zero,algorethem concludes.

BCD2ASC       LDAA  #0                        ; Initialize the blanking flag
              STAA  NO_BLANK

C_TTHOU       LDAA  TEN_THOUS                 ; Check the ?ten_thousands? digit
              ORAA  NO_BLANK
              BNE   NOT_BLANK1

ISBLANK1      LDAA  #' '                      ; It?s blank
              STAA  TEN_THOUS                 ; so store a space
              BRA   C_THOU                    ; and check the ?thousands? digit

NOT_BLANK1    LDAA  TEN_THOUS                 ; Get the ?ten_thousands? digit
              ORAA  #$30                      ; Convert to ascii
              STAA  TEN_THOUS
              LDAA  #$1                       ; Signal that we have seen a ?non-blank? digit
              STAA  NO_BLANK

C_THOU        LDAA  THOUSANDS                 ; Check the thousands digit for blankness
              ORAA  NO_BLANK                  ; If it?s blank and ?no-blank? is still zero
              BNE   NOT_BLANK2

ISBLANK2      LDAA  #' '                      ; Thousands digit is blank
              STAA  THOUSANDS                 ; so store a space
              BRA   C_HUNS                    ; and check the hundreds digit

NOT_BLANK2    LDAA  THOUSANDS                 ; (similar to ?ten_thousands? case)
              ORAA  #$30
              STAA  THOUSANDS
              LDAA  #$1
              STAA  NO_BLANK

C_HUNS        LDAA  HUNDREDS                  ; Check the hundreds digit for blankness
              ORAA  NO_BLANK                  ; If it?s blank and ?no-blank? is still zero
              BNE   NOT_BLANK3

ISBLANK3      LDAA  #' '                      ; Hundreds digit is blank
              STAA  HUNDREDS                  ; so store a space
              BRA   C_TENS                    ; and check the tens digit

NOT_BLANK3    LDAA  HUNDREDS                  ; (similar to ?ten_thousands? case)
              ORAA  #$30
              STAA  HUNDREDS
              LDAA  #$1
              STAA  NO_BLANK

C_TENS        LDAA  TENS                      ; Check the tens digit for blankness
              ORAA  NO_BLANK                  ; If it?s blank and ?no-blank? is still zero
              BNE   NOT_BLANK4

ISBLANK4      LDAA  #' '                      ; Tens digit is blank
              STAA  TENS                      ; so store a space
              BRA   C_UNITS                   ; and check the units digit

NOT_BLANK4    LDAA  TENS                      ; (similar to ?ten_thousands? case)
              ORAA  #$30
              STAA  TENS

C_UNITS       LDAA  UNITS                     ; No blank check necessary, convert to ascii.
              ORAA  #$30
              STAA  UNITS

              RTS                             ; Completed


;***************************************************************************************************
;*                                Interrupt Vectors                                                *
;***************************************************************************************************
                  ORG     $FFFE
                  DC.W    Entry ; Reset Vector
                  ORG     $FFDE
                  DC.W    TOF_ISR ; Timer Overflow Interrupt Vector