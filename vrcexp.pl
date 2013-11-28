# vrcexp.pl, 19 Jun 13

sub print_info
{
   print "Usage: perl vrcexp.pl\n";
   print "   Explore VLC, XBMC and OMX video remote techniques\n";
   print "   Hack code to select player\n";
}

use warnings;
use strict;

use Tk;
use IO::Socket;
use XML::Simple qw(:strict);                # libxml-simple-perl
use JSON::XS;                               # libjson-xs-perl
use Time::HiRes qw(gettimeofday);
use Data::Dumper;

my ($player, $host, $port, $movie_dir);         
#($player, $host, $port, $movie_dir) = ("XBMC", "192.168.1.41", 80, "/home/pi/video/installation_player");         
#($player, $host, $port, $movie_dir) = ("VLC", "192.168.1.37", 8080, "/home/ncvp/winxp/video/installation_player");
($player, $host, $port, $movie_dir) = ("OMX", "192.168.1.41", 8081, "/home/pi/winxp/video/installation_player");
# XBMC on PC interesting, but of no practical use
#($player, $host, $port, $movie_dir) = ("XBMC", "192.168.1.36", 8090, "/home/ncvp/winxp/video/installation_player");

my @movies = ("sync_30min.mp4", "parrot.mp4", "lebesgue.mp4", "guide_mono.mp4");

my $xml = XML::Simple->new();

# total_msecs only to nearest 1000 for VLC
my ($total_msecs, $position_msecs, $percentage) = (0, 0, 0);
my $play_state = "stopped";

my $tx_msecs;                             # Time of request

my @playlist = ();     # (name, id, name, id ...)
my $playlist_ix = 0;

my $sock = IO::Socket::INET->new(Proto=>'tcp', PeerAddr=>$host, PeerPort=>$port, Reuse=>1);
if (!defined($sock))
{
   print "Socket not opened: $!\n";
   exit;
}   

my $constr = "Connected to $player player on " . $sock->peerhost . ":" . $sock->peerport;
$constr .= "\nYou must manually retrieve the status for some of the player and playlist buttons to work correctly";

$sock->autoflush(1);                       # Send immediately
$sock->blocking(0);                        # Turn blocking off

my $mw = new MainWindow(-title=>"Video remote explorer");
$mw->Label(-text=>$constr, -justify=>'left')->pack(-anchor=>'nw', -padx=>5);
$mw->repeat(10, \&read_socket);            # Callback every 10 mSec

$mw->Label(-text=>"Tx:")->pack(-anchor=>'nw', -padx=>5);
my $tx_box = $mw->Scrolled('Text', -font=>"{Arial} 9", -scrollbars=>'se', -height=>5, -width=>100, -wrap=>'none', -state=>'disabled')
                                                                                    ->pack(-anchor=>'nw', -padx=>5);

$mw->Label(-text=>"Rx:")->pack(-anchor=>'nw');
my $rx_box = $mw->Scrolled('Text', -font=>"{Arial} 9", -scrollbars=>'se', -height=>7, -width=>100, -wrap=>'none', -state=>'disabled')
                                                                                    ->pack(-anchor=>'nw', -padx=>5);

my $frm1 = $mw->Frame()->pack(-anchor=>'w', -padx=>5);
my $frm1a = $frm1->Frame()->pack(-side=>'left');
my $frm1b = $frm1->Frame()->pack(-side=>'left', -padx=>10);
my $frm1c = $frm1->Frame()->pack(-side=>'left');

$frm1a->Label(-text=>"Status:")->pack(-anchor=>'nw');
my $status_box = $frm1a->Scrolled('Text', -font=>"{Arial} 9", -scrollbars=>'e', -height=>8, -width=>27, -wrap=>'none', -state=>'disabled')
                                                                                    ->pack(-anchor=>'nw');

$frm1b->Label(-text=>"Playlist:")->pack(-anchor=>'w');
my $playlist_box = $frm1b->Scrolled('Text', -font=>"{Arial} 9", -scrollbars=>'e', -height=>8, -width=>21, -wrap=>'none', -state=>'disabled')
                                                                                    ->pack(-anchor=>'nw');

$frm1c->Label(-text=>"Other info:")->pack(-anchor=>'nw');
my $other_box = $frm1c->Scrolled('Text', -font=>"{Arial} 9", -scrollbars=>'e', -height=>8, -width=>40, -wrap=>'none', -state=>'disabled')
                                                                                    ->pack(-anchor=>'nw');

my $but_frm = $mw->Frame()->pack(-anchor=>'nw', -padx=>5);
my ($row, $clm) = (0, 0);
$but_frm->Label(-text=>"Press to get info:")->grid(-row=>$row++, -column=>0, -sticky=>'w');
$but_frm->Button(-text=>'Get status', -command=>\&get_status)->grid(-row=>$row, -column=>$clm++, -sticky=>'ew');
$but_frm->Button(-text=>'Get playlist', -command=>\&get_playlist)->grid(-row=>$row, -column=>$clm++, -sticky=>'ew');
$row++; $clm = 0;
$but_frm->Label(-text=>"Required functions:")->grid(-row=>$row++, -column=>0, -sticky=>'w');
$but_frm->Button(-text=>'Seek 1 sec', -command=>sub { seek_msecs(1000); })->grid(-row=>$row, -column=>$clm++, -sticky=>'ew');
$but_frm->Button(-text=>'Seek 10 secs', -command=>sub { seek_msecs(10000); })->grid(-row=>$row, -column=>$clm++, -sticky=>'ew');
$but_frm->Button(-text=>'Seek 1 min', -command=>sub { seek_msecs(60000); })->grid(-row=>$row, -column=>$clm++, -sticky=>'ew');
$but_frm->Button(-text=>'Seek 5 min', -command=>sub { seek_msecs(300000); })->grid(-row=>$row, -column=>$clm++, -sticky=>'ew');
$but_frm->Button(-text=>'Seek +1 min', -command=>sub { seek_diff(60000); })->grid(-row=>$row, -column=>$clm++, -sticky=>'ew');
$but_frm->Button(-text=>'Seek -1 min', -command=>sub { seek_diff(-60000); })->grid(-row=>$row, -column=>$clm++, -sticky=>'ew');
$row++; $clm = 0;
$but_frm->Button(-text=>'Pause', -command=>\&pause)->grid(-row=>$row, -column=>$clm++, -sticky=>'ew');
$but_frm->Button(-text=>'Resume', -command=>\&resume)->grid(-row=>$row, -column=>$clm++, -sticky=>'ew');
$but_frm->Button(-text=>'Stop', -command=>\&stop)->grid(-row=>$row, -column=>$clm++, -sticky=>'ew');
$but_frm->Button(-text=>'Shutdown', -command=>\&system_shutdown)->grid(-row=>$row, -column=>$clm++, -sticky=>'ew');
$row++; $clm = 0;
$but_frm->Button(-text=>'Play 0', -command=>sub { play_nth(0) })->grid(-row=>$row, -column=>$clm++, -sticky=>'ew');
$but_frm->Button(-text=>'Play 1', -command=>sub { play_nth(1) })->grid(-row=>$row, -column=>$clm++, -sticky=>'ew');
$but_frm->Button(-text=>'Play 2', -command=>sub { play_nth(2) })->grid(-row=>$row, -column=>$clm++, -sticky=>'ew');
$but_frm->Button(-text=>'Play 3', -command=>sub { play_nth(3) })->grid(-row=>$row, -column=>$clm++, -sticky=>'ew');
#$but_frm->Button(-text=>'Play 4', -command=>sub { play_nth(4) })->grid(-row=>$row, -column=>$clm++, -sticky=>'ew');
$row++; $clm = 0;
$but_frm->Button(-text=>'Clear playlist', -command=>\&clear_playlist)->grid(-row=>$row, -column=>$clm++, -sticky=>'ew');
$but_frm->Button(-text=>'Add movie 1', -command=>sub { add_movie(0); })->grid(-row=>$row, -column=>$clm++, -sticky=>'ew');
$but_frm->Button(-text=>'Add movie 2', -command=>sub { add_movie(1); })->grid(-row=>$row, -column=>$clm++, -sticky=>'ew');
$but_frm->Button(-text=>'Add movie 3', -command=>sub { add_movie(2); })->grid(-row=>$row, -column=>$clm++, -sticky=>'ew');
$but_frm->Button(-text=>'Add movie 4', -command=>sub { add_movie(3); })->grid(-row=>$row, -column=>$clm++, -sticky=>'ew');
#$but_frm->Button(-text=>'Add movie 5', -command=>sub { add_movie(4); })->grid(-row=>$row, -column=>$clm++, -sticky=>'ew');
$row++; $clm = 0;
$but_frm->Label(-text=>"Program control:")->grid(-row=>$row++, -column=>0, -sticky=>'w');
$but_frm->Button(-text=>'Add space', -command=>sub { print "\n\n" })->grid(-row=>$row, -column=>$clm++, -sticky=>'ew');
$but_frm->Button(-text=>'Close socket', -command=>\&close_socket)->grid(-row=>$row, -column=>$clm++, -sticky=>'ew');
if ($player eq 'XBMC')
{
   $row++; $clm = 0;
   $but_frm->Label(-text=>"XBMC testing:")->grid(-row=>$row++, -column=>0, -sticky=>'w');
   $but_frm->Button(-text=>'Introspect', -command=>\&introspect)->grid(-row=>$row, -column=>$clm++, -sticky=>'ew');
   $but_frm->Button(-text=>'Query video lib', -command=>\&query_video_library)->grid(-row=>$row, -column=>$clm++, -sticky=>'ew');
   $but_frm->Button(-text=>'XBMC home', -command=>\&home)->grid(-row=>$row, -column=>$clm++, -sticky=>'ew');
   $but_frm->Button(-text=>'Restart XBMC', -command=>\&application_quit)->grid(-row=>$row, -column=>$clm++, -sticky=>'ew');
}

MainLoop();

my $tod1;
sub get_msecs
{
   if (!defined($tod1))
      { $tod1 = gettimeofday(); }
   my $tod2 = gettimeofday() - $tod1;
   return int($tod2*1000);
}

my ($rx_hdr, $rx_data, $rx_got_blank, $rx_data_length);

# Common HTTP part
sub read_socket
{
   while (my $line = <$sock>)
   { 
#      print "***$line"; 
      if ($line =~ /^HTTP.*/)
      {
         $rx_hdr = "";
         $rx_data = "";
         $rx_got_blank = 0;
         $rx_data_length = 0;
      }
      if ($line =~ /^Content-Length: (.*)/)
      {
         $rx_data_length = $1;
      }
      if ($rx_got_blank)
      {
         $rx_data .= $line;
      }
      else
      {
         $rx_hdr .= $line;
      }
      if (length($line) <= 2)
      {
         $rx_got_blank = 1;
      }
      if ($rx_data_length > 0 && length($rx_data) >= $rx_data_length)
      {
         $rx_got_blank = 0;
         $rx_box->configure(-state=>'normal');

         $rx_box->delete("1.0", "end");
         $rx_box->insert('1.0', "$rx_hdr$rx_data");
         $rx_box->configure(-state=>'disabled');

         if ($player eq 'VLC')
            { read_socket_vlc(); }
         elsif ( $player eq 'XBMC' )
            { read_socket_xbmc(); }
         elsif ( $player eq 'OMX' )
            { read_socket_omx(); }
         else
         { 
            print "read_socket(): Unknown player type $player\n";
            exit();
         }
      }
   }
}

sub set_playlist_box
{
   $playlist_box->configure(-state=>'normal');
   $playlist_box->delete("1.0", "end");
   for (my $i = 0; $i < @playlist; $i += 2)
   { 
      $playlist_box->Insert("$playlist[$i]\t$playlist[$i + 1]\n");
   }
   $playlist_box->configure(-state=>'disabled');
}

sub set_status_box
{
   $status_box->configure(-state=>'normal');
   $status_box->delete("1.0", "end");
   $status_box->Insert("Play state: $play_state\n");
   $status_box->Insert("Pos msecs: $position_msecs\n");
   $status_box->configure(-state=>'disabled');
}

sub write_other_box
{
   my $str = shift;
   $other_box->configure(-state=>'normal');
   $other_box->delete("1.0", "end");
   $other_box->Insert($str);
   $other_box->configure(-state=>'disabled');
}

sub read_socket_omx
{
   my @lines = split(/\n/, $rx_data);
   foreach my $line (@lines) 
   {
      # Playlist. Complete playlist in single line
      if ($line =~ s/l://)
      {
         @playlist = ();
         my @movies = split(/,/, $line);
         for (my $i = 0; $i < @movies; $i++)
         { 
            push @playlist, $movies[$i], $i; 
         }
      }         
      if ($line =~ s/s://)
      { 
         $line =~ /([^\d]*)(\d*)/;
         $play_state = $1; 
         $position_msecs = $2; 
      }
   }
   set_status_box(); 
   set_playlist_box(); 
   write_other_box("Turnround: " . (get_msecs() - $tx_msecs) . " mSec\n");
}

sub time2msecs
{
   my $ref = shift;
   my $msecs = $ref->{'milliseconds'};
   $msecs += $ref->{'seconds'}*1000;
   $msecs += $ref->{'minutes'}*1000*60;
   $msecs += $ref->{'hours'}*1000*60*60;
   return $msecs;
}

# JSON data
sub read_socket_xbmc
{
   my $rx_json = decode_json($rx_data);
# print Dumper($rx_json);
   
   if ($rx_json->{'error'})
   { 
      print "jsonrpc error: $rx_json->{'error'}->{'message'}\n";
      return; 
   }
            
   if ($rx_json->{'result'} eq 'OK')
      { return; }
# print "£££", Dumper($rx_json->{'result'});
                     
   # Playlist
   if ($rx_json->{'result'}->{'limits'})
   {
      @playlist = ();
      $playlist_box->configure(-state=>'normal');
      $playlist_box->delete("1.0", "end");
      for (my $i = 0; defined($rx_json->{'result'}->{'items'}[$i]->{'label'}); $i++)
      { 
         push @playlist, $rx_json->{'result'}->{'items'}[$i]->{'label'}, $i; 
         $playlist_box->Insert("$rx_json->{'result'}->{'items'}[$i]->{'label'}\t$i\n");
      }
      $playlist_box->configure(-state=>'disabled');
   }         

   # Status
   $status_box->configure(-state=>'normal');
   $status_box->delete("1.0", "end");
   if (defined($rx_json->{'result'}->{'position'}))              # position of file in playlist!
   {
      $playlist_ix = $rx_json->{'result'}->{'position'};
      $status_box->Insert("Filename:\t$playlist[2*$rx_json->{'result'}->{'position'}]\n");
   }         
   if (defined($rx_json->{'result'}->{'percentage'}))
   {
      $percentage = $rx_json->{'result'}->{'percentage'};
      $status_box->Insert("%: $percentage\n");
   }  
   if (defined($rx_json->{'result'}->{'speed'}))
   {
      $play_state = ($rx_json->{'result'}->{'speed'} == 1) ? "playing" : "paused";
   }         
   if (defined($rx_json->{'result'}->{'time'}))
   {
      $position_msecs = time2msecs($rx_json->{'result'}->{'time'});
      $status_box->Insert("Pos msecs: $position_msecs\n");
   }  
   if (defined($rx_json->{'result'}->{'totaltime'}))
   {
      $total_msecs = time2msecs($rx_json->{'result'}->{'totaltime'});
      $status_box->Insert("Total msecs: $total_msecs\n");
   }  
   $status_box->Insert("Play state: $play_state\n");
   $status_box->configure(-state=>'disabled');
}

sub read_socket_vlc
{
   # Extract xml
   $rx_data =~ s/<?.*?>//m;                      # Remove leading xml specifier
# print "\n$rx_data\n";
   my $rx_xml = $xml->XMLin($rx_data, ForceArray=>1, KeyAttr=>"");        # ForceArray cos movie can appear more than once
# print Dumper($rx_xml);
         
   if ($rx_xml->{'node'})
   {
      # Playlist
      @playlist = ();
      my $pl = $rx_xml->{'node'}[0]{'leaf'};
      $playlist_box->configure(-state=>'normal');
      $playlist_box->delete("1.0", "end");
      my $playlist_length = defined($pl) ? int(@$pl) : 0;
      for (my $i = 0; $i < $playlist_length; $i++)
      { 
         push @playlist, $$pl[$i]{'name'}, $$pl[$i]{'id'}; 
         $playlist_box->Insert("$$pl[$i]{'name'}\t$$pl[$i]{'id'}\n"); 
      }
      $playlist_box->configure(-state=>'disabled');
   }

   if ($rx_xml->{'state'})
   {
      # State
      $status_box->configure(-state=>'normal');
      $status_box->delete("1.0", "end");
      $other_box->configure(-state=>'normal');
      $other_box->delete("1.0", "end");
      $other_box->Insert("VLC version: $rx_xml->{'version'}[0]\n");
      $play_state = $rx_xml->{'state'}[0];
      $status_box->Insert("State: $play_state\n");
# $other_box->Insert("Volume: $rx_xml->{'volume'}[0]\n");
      $total_msecs = $rx_xml->{'length'}[0]*1000;
      $status_box->Insert("Length: $rx_xml->{'length'}[0]\n");
# $other_box->Insert("Fullscreen: $rx_xml->{'fullscreen'}[0]\n");
      $status_box->Insert("Time: $rx_xml->{'time'}[0]\n");
      my $pos_pc = $rx_xml->{'position'}[0];
      $status_box->Insert("Position: $pos_pc\n");
      $position_msecs = $total_msecs*$pos_pc;

      my $chans = $rx_xml->{'information'}[0]->{'category'};
      if (defined($$chans[1]))
      {
         for (my $j = 0; defined($$chans[0]->{'info'}[$j]); $j++)
         { 
            my $name = $$chans[0]->{'info'}[$j]->{'name'};
            if ($name eq 'filename')
               { $status_box->Insert("$name: $$chans[0]->{'info'}[$j]->{'content'}\n"); }
            elsif ($name ne 'setting')
               { $other_box->Insert("$name: $$chans[0]->{'info'}[$j]->{'content'}\n"); }
         }
         for (my $j = 0; defined($$chans[1]->{'info'}[$j]); $j++)
         {
            my $name = $$chans[1]->{'info'}[$j]->{'name'};
            if ($name ne 'Type')
               { $other_box->Insert("$name: $$chans[1]->{'info'}[$j]->{'content'}\n"); }
         }
      }
      $status_box->configure(-state=>'disabled');
      $other_box->configure(-state=>'disabled');
   }
}

sub close_socket
{
   print "\n\n";
   close $sock; 
   exit;
}

############
# Requests #
############

# Identical to http_get_vlc()
sub http_get_omx
{
   my $req = shift;
   my $str = "GET $req HTTP/1.1\n";
   $str .= "\n";
   
   $tx_box->configure(-state=>'normal');
   $tx_box->delete("1.0", "end");
   $tx_box->insert('1.0', $str);
   $tx_box->configure(-state=>'disabled');
   
   $tx_msecs = get_msecs();
   print $sock $str;
}

sub http_get_vlc
{
   my $req = shift;
   my $str = "GET $req HTTP/1.1\n";
   $str .= "\n";
   
   $tx_box->configure(-state=>'normal');
   $tx_box->delete("1.0", "end");
   $tx_box->insert('1.0', $str);
   $tx_box->configure(-state=>'disabled');
   
   $tx_msecs = get_msecs();
   print $sock $str;
}

sub http_post_xbmc
{
   my $json = shift;
   my $len = length($json);
   my $str = "POST /jsonrpc HTTP/1.1\n";
   $str .= "Content-Type: application/json; charset=UTF-8\n";       # Mandatory according to spec, but works without
   $str .= "Content-Length: $len\n";
   $str .= "\n";
   $str .= $json;
   
   $tx_box->configure(-state=>'normal');
   $tx_box->delete("1.0", "end");
   $tx_box->insert('1.0', $str);
   $tx_box->configure(-state=>'disabled');
   
   $tx_msecs = get_msecs();
   print $sock $str;
}

###########
# Vplayer #
###########

sub get_status
{
   if ($player eq "XBMC")
   { 
      my $json = '{"jsonrpc":"2.0","method":"Player.GetProperties","id":42,"params":{"playerid":1,' .
                  '"properties":[' .
                  '"playlistid","speed","position","totaltime","time","percentage"' .
                  ']}}}';
      http_post_xbmc($json); 
   }
   elsif ($player eq "VLC")
   { 
      http_get_vlc("/requests/status.xml"); 
   }
   elsif ($player eq "OMX")
   { 
      http_get_omx("/status"); 
   }
   else
   {
      print "get_status(): Unknown player type $player\n";
      exit();
   }
}

# Fundamental command for OMX
sub seek_msecs
{
   my $msecs = shift;
   if ($player eq "XBMC" || $player eq "VLC")
   {
      my $pc = ($msecs/$total_msecs)*100;
      seek_pc($pc);
   }
   elsif ($player eq "OMX")
   { 
      http_get_omx("/status?seek&$msecs");
   }
   else      
   {
      print "seek(): Unknown player type $player\n";
      exit();
   }
}

sub seek_diff
{
   my $diff = shift;
   seek_msecs($position_msecs + $diff);
}

# Fundamental command for VLC and XBMC 
sub seek_pc
{
   my $pc = shift;
   if ($player eq "XBMC")
   { 
      http_post_xbmc('{"jsonrpc":"2.0","id":1,"method":"Player.Seek","params":{"playerid":1,"value":' . $pc . '}}');
   }
   elsif ($player eq "VLC")
   { 
      http_get_vlc("/requests/status.xml?command=seek&val=$pc%");          # This seems to have a finer grain
   }
   elsif ($player eq "OMX")
   { 
      my $msecs = ($total_msecs*$pc)/100;
      seek_msecs($msecs);
   }
   else      
   {
      print "play_nth(): Unknown player type $player\n";
      exit();
   }
}

sub play_nth
{
   if (int(@playlist) < 2)
   {
      print "Play list empty\n";
      return;
   }
   my $n = shift;
   if ($player eq "XBMC")
   { 
      http_post_xbmc('{"jsonrpc":"2.0","method":"Player.Open","params":{"item":{"playlistid":1,"position":' . $n . '}},"id":1}');
   }
   elsif ($player eq "VLC")
   { 
      my $pid = $playlist[2*$n + 1];
      http_get_vlc("/requests/status.xml?command=pl_play&id=$pid");
   }
   elsif ($player eq "OMX")
   { 
      http_get_omx("/status?play&$n");
   }
   else      
   {
      print "play_nth(): Unknown player type $player\n";
      exit();
   }
}

# XBMC only has a toggle
sub pause
{
   if ($player eq "XBMC")
   { 
      if ($play_state eq "playing")
         { http_post_xbmc('{"jsonrpc":"2.0","method":"Player.PlayPause","id":1,"params":{"playerid":1}}'); }
   }
   elsif ($player eq "VLC")
   { 
      http_get_vlc("/requests/status.xml?command=pl_forcepause"); 
   }
   elsif ($player eq "OMX")
   { 
      http_get_omx("/status?pause");
   }
   else      
   {
      print "pause(): Unknown player type $player\n";
      exit();
   }
}

# XBMC only has a toggle
sub resume
{
   if ($player eq "XBMC")
   { 
      if ($play_state eq "paused")
         { http_post_xbmc('{"jsonrpc":"2.0","method":"Player.PlayPause","id":1,"params":{"playerid":1}}'); }
   }
   elsif ($player eq "VLC")
   { 
      http_get_vlc("/requests/status.xml?command=pl_forceresume"); 
   }
   elsif ($player eq "OMX")
   { 
      http_get_omx("/status?resume");
   }
   else      
   {
      print "resume(): Unknown player type $player\n";
      exit();
   }
}

sub stop
{
   if ($player eq "XBMC")
   { 
      http_post_xbmc("{\"jsonrpc\":\"2.0\",\"method\":\"Player.Stop\",\"id\":1,\"params\":{\"playerid\":1}}"); 
   }
   elsif ($player eq "VLC")
   { 
      http_get_vlc("/requests/status.xml?command=pl_stop"); 
   }
   elsif ($player eq "OMX")
   { 
      http_get_omx("/status?stop");
   }
   else      
   {
      print "stop(): Unknown player type $player\n";
      exit();
   }
}

############
# Playlist #
############

sub get_playlist
{
   if ($player eq "XBMC")
   { 
      http_post_xbmc('{"jsonrpc":"2.0","method":"Playlist.GetItems","id":1,' .
                     '"params":{"playlistid":1,"properties":["runtime"]}}'); 
   }
   elsif ($player eq "VLC")
   { 
      http_get_vlc("/requests/playlist.xml"); 
   }
   elsif ($player eq "OMX")
   { 
      http_get_omx("/plist"); 
   }
   else      
   {
      print "get_playlist(): Unknown player type $player\n";
      exit();
   }
}

sub clear_playlist
{
   if ($player eq "XBMC")
   { 
      http_post_xbmc('{"jsonrpc":"2.0","method":"Playlist.Clear","id":1,"params":{"playlistid":1}}'); 
   }
   elsif ($player eq "VLC")
   { 
      http_get_vlc("/requests/playlist.xml?command=pl_empty"); 
   }
   elsif ($player eq "OMX")
   { 
      http_get_omx("/plist?clear"); 
   }
   else      
   {
      print "clear_playlist(): Unknown player type $player\n";
      exit();
   }
}

# Add a movie to playlist
sub add_movie
{
   my $ix = shift;
   my $movie_file = $movies[$ix];
   my $movie_path = "$movie_dir/$movie_file";
   if ($player eq "XBMC")
   { 
      http_post_xbmc('{"id":1,"jsonrpc":"2.0","method":"Playlist.Add","params":{"item":{"file":"' . $movie_path . '"},"playlistid":1}}'); 
   }
   elsif ($player eq "VLC")
   { 
      http_get_vlc("/requests/playlist.xml?command=in_enqueue&input=file://$movie_path"); 
   }
   elsif ($player eq "OMX")
   { 
      http_get_omx("/plist?addm&$movie_path"); 
   }
   else      
   {
      print "add_movie(): Unknown player type $player\n";
      exit();
   }
}

##########
# System #
##########

# shutdown -h now. Required for Raspberry Pis
sub system_shutdown
{
   if ($player eq "XBMC")
   { 
      my $json = '{"jsonrpc":"2.0","method":"System.Shutdown","id":1}';
      http_post_xbmc($json); 
   }
   elsif ($player eq "OMX")
   { 
      http_get_omx("/status?shutdown"); 
   }
   else
   {
      print "system_shutdown(): not implemented for $player\n";
   }
}

#############
# XBMC only #
#############

# Interesting. But only use in extremis if an answer can't be found elsewhere
sub introspect
{
   if ($player eq "XBMC")
   { 
      my $json = '{"jsonrpc":"2.0","method":"JSONRPC.Introspect","params":{"filter":{"id":"Application.Quit","type":"method"}},"id":1}';
      http_post_xbmc($json); 
   }
   else
      { print "\nXBMC only\n"; }
}

# This works, but it clears the playlist
sub player_open_file
{
   if ($player eq "XBMC")
   { 
      http_post_xbmc('{"jsonrpc":"2.0","method":"Player.Open","id":1,"params":[{"file":"/home/pi/video/test/parrot.mp4"}]}}'); 
   }
   else
      { print "\nXBMC only\n"; }
}

# No use at all
sub query_video_library
{
   if ($player eq "XBMC")
   { 
      my $json = '{"jsonrpc": "2.0", "method": "VideoLibrary.GetMovies", "params": { "filter":' .
         '{"field": "playcount", "operator": "is", "value": "0"}, "limits": { "start" : 0, "end": 75 }, "properties" :' .
         '["art", "rating", "thumbnail", "playcount", "file"], "sort": { "order": "ascending", "method":' .
         '"label", "ignorearticle": true } }, "id": "libMovies"}';
      http_post_xbmc($json); 
   }
   else
      { print "\nXBMC only\n"; }
}

# This causes XBMC to restart. Could be handy in a tangle
sub application_quit
{
   if ($player eq "XBMC")
   { 
      my $json = '{"jsonrpc":"2.0","method":"Application.Quit","id":1}';
      http_post_xbmc($json); 
   }
   else
      { print "\nXBMC only\n"; }
}

# Go to XBMC home screen. Not useful
sub home
{
   if ($player eq "XBMC")
   { 
      my $json = '{"jsonrpc":"2.0","method":"Input.Home","id":1}';
      http_post_xbmc($json); 
   }
   else
      { print "\nXBMC only\n"; }
}


