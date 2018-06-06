#!/usr/bin/env perl

=head1 server.pl

 Though this code ( and client.pl ) use setsockopt() to set the TCP buffer size,
 there does not seem to be any method that actually works.

 The buffer size reported by getsockopt() remains constant regardless of attempts to change it

=cut
 
use warnings;
use strict;
use IO::Socket::INET;
use Socket qw(SOL_SOCKET SO_RCVBUF IPPROTO_IP IP_TTL);
#use Data::Dumper;
use Time::HiRes qw(gettimeofday tv_interval);

my $port = 4242;

# now setting bufsz dynamically via message from the client
# so this bit is not really necessary - leaving it here for now though

my $bufsz=$ARGV[0];

$bufsz = 2048 unless $bufsz;

# minimal sanity check for bufsz

unless ( $bufsz =~ /^[[:digit:]]+$/ ) {
	die "bufsz of $bufsz is not an integer\n";
}

# bufsz really should be a power of 2
# $log will be an integer if a power of 2
my $log = log($bufsz) / log(2);
unless ( $log =~ /^[[:digit:]]+$/ ) {

	die "bufsz of $bufsz is not a power of 2\n";
}

# bufsz should be LT 8M
if ($bufsz > (8 * 2**20) ) {
	die "bufszs of $bufsz is GT 8M (8388608)\n";
}

# report on every megabyte sent

my %rptIntervals = ();

foreach my $i ( 1..30 ) {
	if ($i > 20 ) { $rptIntervals{2**$i} = 1 }
	else { $rptIntervals{2**$i} = 2**20 / 2**$i}
}

my $reportInterval = $rptIntervals{$bufsz};
$reportInterval = 1 unless defined($reportInterval);
print "Report Interval: $reportInterval\n";

#foreach my $i ( sort { $a <=> $b } keys %rptIntervals ) {
	#print "$i: $rptIntervals{$i}\n";
#}

#exit;
 
$| = 1; # flush stdout
 
my $proto = getprotobyname('tcp');    #get the tcp protocol
 
my $sock = IO::Socket::INET->new(LocalPort => $port, Proto => $proto, Listen  => 1, Reuse => 1)
         or die "Cannot create socket: $@";

$sock->setsockopt(SOL_SOCKET, SO_RCVBUF, $bufsz) or
	die "setsockopt: $!";

print "Initial Receive Buffer is ", $sock->getsockopt(SOL_SOCKET, SO_RCVBUF),
	" bytes\n";

 
listen($sock , 10);
print "Server is now listening ...\n";
print "Initial Buffer size set to: $bufsz\n";
 

#accept incoming connections and talk to clients
while(1)
{
	my ($packets, $totalBytes, $sockElapsed) = (0,0,0);
	my($client);
	my $addrinfo = accept($client , $sock);
 
	my($clientPort, $iaddr) = sockaddr_in($addrinfo);
	my $name = gethostbyaddr($iaddr, AF_INET);
 
	print "Connection accepted from $name : $clientPort \n";
 
	# client first sends the bufsz
	my $newBufSZ = <$client>;
	print "New Desired Buffer Size set to $newBufSZ\n";

	$sock->setsockopt(SOL_SOCKET, SO_RCVBUF, $newBufSZ) or
		die "setsockopt: $!";

	print "Receive Buffer is ", $sock->getsockopt(SOL_SOCKET, SO_RCVBUF),
		" bytes\n";

	chomp $newBufSZ;
	$reportInterval = $rptIntervals{$newBufSZ};
	$reportInterval = 1 unless defined($reportInterval);
	print "Report Interval: $reportInterval\n";
	
	my $line;
	my $startTime = [gettimeofday];
	my $t0=[gettimeofday];
	while(my $r=read $client,$line,$newBufSZ) {

		#print "Read $r bytes\n";
		my $t1 = [gettimeofday];
		my $rcvtim = tv_interval $t0, $t1;

		$sockElapsed += $rcvtim;
		$totalBytes += $r;
		$packets++;

		#printf "%4.6f\n", $rcvtim;
		#print "bytes read: $r\n" unless  $packets%$reportInterval;
		print '.' unless $packets%$reportInterval;

		# needs to be the last line in the loop`
		$t0 = [gettimeofday];
	}

	my $endTime = [gettimeofday];
	my $totalElapsed = tv_interval $startTime, $endTime;

	print "\n\n";

	next if $totalBytes < 1;

	print "Start Time: ", $startTime->[0] + ($startTime->[1]/1000000),"\n";
	print "  End Time: ", $endTime->[0] + ($endTime->[1]/1000000),"\n";
	print "totElapsed: $totalElapsed\n";

	printf qq{

Packets Received: %u
Bytes Received: %u
Total Elapsed Seconds: %10.6f
Network Elapsed Seconds: %10.6f
Average milliseconds: %3.9f
Avg milliseconds/MiB: %3.9f

},
	$packets,
	$totalBytes,
	$totalElapsed,
	$sockElapsed,
	$sockElapsed / $packets  * 1000,
	$sockElapsed /  ($totalBytes / 2**20)  * 1000
;

	print "\n", '-'x 80 , "\n";

	print "\nSocket closed - accepting new connections\n";
}
 
#close the socket
close($sock);
exit(0); 

