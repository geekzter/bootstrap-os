function  Disable-HyperV {
	net stop vhdsvc
	net stop nvspwmi
	net stop vmms

	sc.exe config vhdsvc start= demand
	sc.exe config nvspwmi start= demand
	sc.exe config vmms start= demand
	
	sc.exe config hvboot start= disabled
}

function  Enable-HyperV {
	sc.exe config vhdsvc  start= delayed-auto
	sc.exe config nvspwmi start= delayed-auto
	sc.exe config vmms    start= delayed-auto

	net start vhdsvc
	net start nvspwmi
	net start vmms

	sc.exe config hvboot start= boot
	net start hvboot
}