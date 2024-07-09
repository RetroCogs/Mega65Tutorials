KICK=/Users/colinreed/Applications/KickAss/KickAss65CE02-5.24f.jar
APPNAME=tutorial_4_ncm
C1541=/opt/homebrew/Cellar/vice/3.7.1/bin/c1541
XEMU=/Applications/Xemu/xmega65.app/Contents/MacOS/xmega65
PNG65=node ./build/aseparse65/png65.js
LDTK65=node ./build/ldtk65/ldtk65.js
MEGA65_FTP=~/Applications/Mega65/mega65_ftp.osx
EMEGA65_FTP=~/Documents/MEGA65/mega65_ftp.osx
ETHERLOAD=~/Documents/MEGA65/etherload.osx
ETHERLOAD_ARGS=-r $(APPNAME).prg

JTAG=/dev/cu.usbserial-2516330596481
DISKNAME=FSHOT.D81

all: code

code: 
	$(PNG65) chars --fcm --size 32,32 --input "fcm_test.png" --output "." --nofill
	$(PNG65) chars --ncm --size 32,32 --input "ncm_test.png" --output "." --nofill
	$(PNG65) sprites --ncm --size 16,16 --input "ncm_sprite.png" --output "." --nofill
	java -cp $(KICK) kickass.KickAssembler65CE02 -vicesymbols -showmem $(APPNAME).asm

run: all
	$(XEMU) -prg $(APPNAME).prg -uartmon :4510 -videostd 0

push: all
	$(MEGA65_FTP) -F -l $(JTAG) -c "put $(DISKNAME)" -c "quit"

eth: all
	$(EMEGA65_FTP) -F -i 192.168.0.255 -c "put $(DISKNAME)" -c "quit"

qq: all
	$(ETHERLOAD) $(ETHERLOAD_ARGS)
	

