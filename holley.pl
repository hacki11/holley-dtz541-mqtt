#!/usr/bin/perl
# Stromzaehler Holley DTZ541 auslesen und in logdatei speichern
# SML-Daten
#
# Hilfen waren u.a.
# http://www.stefan-weigert.de/php_loader/sml.php
# http://www.schatenseite.de/2016/05/30/smart-message-language-stromzahler-auslesen/comment-page-1/
# https://www.photovoltaikforum.com/thread/134055-lesekopf-holley-dtz-541-zeba/?pageNo=4



use Device::SerialPort;
use Time::HiRes qw(sleep gettimeofday tv_interval usleep);
use Net::MQTT::Simple "localhost";

#$socket = "/dev/ttyUSB1";
my $socket = new Device::SerialPort("/dev/ttyUSB0");
$socket->user_msg(ON);
$socket->error_msg(ON);
$socket->buffers(4096, 4096);
$socket->baudrate(9600)     || die 'fail setting baudrate';
$socket->databits(8)        || die 'fail setting databits';
$socket->stopbits(1)        || die 'fail setting stopbits';
$socket->parity("none")     || die 'fail setting stopbits';
$socket->purge_all();
$socket->write_settings     || die 'fail setting';
$socket->read_char_time(0);       # don't wait for each character
$socket->read_const_time(100);    # 0.1 sec per unfulfilled "read"


$STALL_DEFAULT=1; # how many seconds to wait for new input

$timeout=$STALL_DEFAULT;




$i=0;
$start=0;
$buffer="";
$firsttime=1;

while (1) {
    $timeout=1;
    $unix_time = time;
    ($jahr, $monat, $tag, $stunde, $minute, $sekunde) = (localtime)[5,4,3,2,1,0];
    $monat=$monat+1;
    $jahr=$jahr+1900;

    if ($tag<10) {$tag='0'.$tag;}
    if ($monat<10) {$monat='0'.$monat;}
    if ($stunde<10) {$stunde='0'.$stunde;}
    if ($minute<10) {$minute='0'.$minute;}
    if ($sekunde<10) {$sekunde='0'.$sekunde;}

    $log="/tmp/Z0_Wert_".$jahr.$monat.$tag.".log";
    $logdatei_stand="/tmp/Z0_Stand_".$jahr.$monat.$tag.".log";



    my $chars=0;
    my $buffer="";
    while ($timeout>0) {
       my ($count,$answer)=$socket->read(1024); # will read _up to_ 1024 chars
       if ($count > 0) {
	    $chars+=$count;
            $buffer.=$answer;
	    #print $count ." Gesehen: ".$answer ."\n";
	    #print $count ." Gesehen.\n";
               # Check here to see if what we want is in the $buffer
               # say "last" if we find it
	decode(unpack('H*',$buffer));

       }
       else {
               $timeout--;
       }
    }

    if ($timeout==0) {
	#print "Bisher nix gesehen.\n";
	sleep(1);
    }

    
    
} # while

sub decode {
    my $message=$_[0];
    undef $P,$U1,$U2,$U3;
    my $val="";
    my $length="";


#### Leistung
#77
#07 01 00 10 07 00 ff<->		Wirkleistung, Obis16, .7.0

    $P_idx = index($message, "77070100100700ff0101621b5200");
    if ($P_idx > 200) {
	#print "P Start: ".$P_idx ."\n";
	$P_raw=substr($message,$P_idx+28,10);
	#print "P raw: ".$P_raw ."\n";
	($length,$val)=decode_byte($P_raw);
	$P=unpack('s>*',pack('H*',$P_raw));
	$P=$val;
	#print "1: ".pack('H*',$P_raw)."\n";
	#$P_dec -= 0x1000 if $P_dec >= 0x8000;
	print "     P: ".$P." Watt\n";
	publish "power/p" => $P;
    }

    
# Export
    $Aminus_idx = index($message, "77070100020800ff65");
    if ($Aminus_idx > 200) {
    #print "P Start: ".$P_idx ."\n";
	$Aminus_raw=substr($message,$Aminus_idx+44,100);
	#print "raw: ".$Aminus_raw ."\n";
	($length,$val)=decode_byte($Aminus_raw);
	$Aminus=$val/10000;
	print "Stand Export: ".$Aminus." kWh\n";
    }

# U1
    $U1_idx = index($message, "77070100200700ff0101622352ff63");
    if ($U1_idx > 200) {
    #print "P Start: ".$P_idx ."\n";
	$U1_raw=substr($message,$U1_idx+30,4);
#	print "raw: ".$U1_raw ."\n";
	$U1=unpack('s>*',pack('H*',$U1_raw))/10;
	print "U1: ".$U1."\n";
    }

# U2
    $U2_idx = index($message, "77070100340700ff0101622352ff63");
    if ($U2_idx > 200) {
    #print "P Start: ".$P_idx ."\n";
	$U2_raw=substr($message,$U2_idx+30,4);
	$U2=unpack('s>*',pack('H*',$U2_raw))/10;
	print "U2: ".$U2."\n";
    }


# U3
    $U3_idx = index($message, "77070100480700ff0101622352ff63");
    if ($U3_idx > 200) {
    #print "P Start: ".$P_idx ."\n";
	$U3_raw=substr($message,$U3_idx+30,4);
	$U3=unpack('s>*',pack('H*',$U3_raw))/10;
	print "U3: ".$U3."\n";
    }


# f
#770701000e0700ff0101622c52ff63 01f3
    $f_idx = index($message, "770701000e0700ff0101622c52ff63");
    if ($f_idx > 200) {
	#print "P Start: ".$P_idx ."\n";
	$f_raw=substr($message,$f_idx+30,4);
#	print "f raw: ".$f_raw ."\n";
	$f=unpack('s>*',pack('H*',$f_raw))/10;
	#print "1: ".pack('H*',$P_raw)."\n";
	#$P_dec -= 0x1000 if $P_dec >= 0x8000;
	print "f: ".$f." Hz\n";
    }

# I1
    $I1_idx = index($message, "770701001f0700ff0101");
    if ($I1_idx > 200) {
	$I1_raw=substr($message,$I1_idx+28,10);
	($length,$val)=decode_byte($I1_raw);
	$I1=$val/100;
	print "I1: ".$I1." \n";
	publish "power/i1" => $I1;
    }

# I2
	$I2_idx = index($message, "77070100330700ff0101");
    if ($I2_idx > 200) {
	$I2_raw=substr($message,$I2_idx+28,10);
	($length,$val)=decode_byte($I2_raw);
	$I2=$val/100;
	print "I2: ".$I2." \n";
	publish "power/i2" => $I2;
    }
# I3
    $I3_idx = index($message, "77070100470700ff0101");
    if ($I3_idx > 200) {
	$I3_raw=substr($message,$I3_idx+28,10);
	($length,$val)=decode_byte($I3_raw);
	$I3=$val/100;
	print "I3: ".$I3." \n";
	publish "power/i3" => $I3;
    }

# Winkel
# 07 01 00 51 07 01 ff
    $ph1_idx = index($message, "77070100510701ff0101");
    if ($ph1_idx > 200) {
	$ph1_raw=substr($message,$ph1_idx+28,10);
	($length,$val)=decode_byte($ph1_raw);
	$ph1=$val;
	print "ph: ".$ph1." \n";
    }

# Winkel2
# 070100510702ff
    $ph2_idx = index($message, "77070100510702ff0101");
    if ($ph2_idx > 200) {
	$ph2_raw=substr($message,$ph2_idx+28,10);
	($length,$val)=decode_byte($ph2_raw);
	$ph2=$val;
	print "ph: ".$ph2." \n";
    }

# Phi1
    $phi1_idx = index($message, "77070100510704ff0101");
    if ($phi1_idx > 200) {
	$phi1_raw=substr($message,$phi1_idx+28,10);
	($length,$val)=decode_byte($phi1_raw);
	$phi1=$val;
	print "phi1: ".$phi1." \n";
    }

# Phi2
    $phi2_idx = index($message, "7707010051070fff0101");
    if ($phi2_idx > 200) {
	$phi2_raw=substr($message,$phi2_idx+28,10);
	($length,$val)=decode_byte($phi2_raw);
	$phi2=$val;
	print "phi2: ".$phi2." \n";
    }

# Phi3
    $phi3_idx = index($message, "7707010051071aff0101");
    if ($phi3_idx > 200) {
	$phi3_raw=substr($message,$phi3_idx+28,10);
	($length,$val)=decode_byte($phi3_raw);
	$phi3=$val;
	print "phi3: ".$phi3." \n";
    }


# Verbrauch d1
#07 01 00 01 08 00 60
    $d1_idx = index($message, "77070100010800ff");
    if ($d1_idx > 200) {
	$d1_raw=substr($message,$d1_idx+44,10);
	($length,$val)=decode_byte($d1_raw);
	$d1=$val*0.1;
	print "1.8.0 (Wh): ".$d1." \n";
	publish "power/counter" => $d1;
    }


### Daten schreiben
    #open (LOG,">>",$log) or die "Logdatei kann nicht geschrieben werden";
    #print LOG $jahr.$monat.$tag."T".$stunde.$minute.$sekunde.';'.$unix_time.';'.$P.';'.$f.';'.$U1.';'.$U2.';'.$U3.';'.$I1.';'.$I2.';'.$I3.';'.$ph1.';'.$ph2.';'.$phi1.';'.$ph2.';'.$phi3.";\n";
    #close(LOG);


# Alle 5 Minuten die Staende loggen
    if ( ($minute % 5 == 0) && ($firsttime ==1) ) {
	#print " !!!!!!!!!!!!!!!!!    Staende !!!!!\n";
	#open (LOG_STAND,">>",$logdatei_stand) or die "Logdatei kann nicht geschrieben werden";
	#print LOG_STAND $jahr.$monat.$tag."T".$stunde.$minute.$sekunde.";".$unix_time.";".$d1.";".$Aminus.";\n";
	#close(LOG_STAND);
	$firsttime=0;
    }
    if ($minute % 5 != 0) {
	$firsttime=1;
    }
}


sub decode_byte {
    my $message=$_[0];
    my $length=0;
    my $val="";

    $TL=substr($message,0,2);
#    print "TL:".$TL."\n";
    if ($TL eq "52") {				# int8
	$val_raw=substr($message,2,2);
	$val=unpack('c*',pack('H*',$val_raw));
	$length=4;
    } elsif ($TL eq "53") {			# int16
	$val_raw=substr($message,2,4);
	$val=unpack('s>*',pack('H*',$val_raw));
	$length=6;
    } elsif ($TL eq "62") {			# Unsigned8
	$val_raw=substr($message,2,2);
	$val=unpack('W*',pack('H*',$val_raw));
	$length=4;
    } elsif ($TL eq "63") {			# Unsigned16
	$val_raw=substr($message,2,4);
	$val=unpack('S>*',pack('H*',$val_raw));
	$length=6;
    } elsif ($TL eq "65") {			# Unsigned32
	$val_raw=substr($message,2,8);
#	print "Raw: ".$val_raw."\n";
	$val=unpack('L>*',pack('H*',$val_raw));
	$length=10;
    } else {
	print "TL unbekannt: ".$TL."\n";
    }
#    print "Laenge: ".$length.", Wert: ".$val."\n";
    return($length,$val);
}
