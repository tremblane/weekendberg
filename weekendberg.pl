#!/usr/local/bin/perl 
#use warnings;

use lib '/ws/jadew-rtp/perllib';
use WWW::Mechanize;
use XML::Simple;
use Data::Dumper;
use Switch;

# Magic Numbers
my $eng_staffing_alert_threshold = 2;
my $refresh_cycle = 15; #seconds between refreshes

my $username = $ENV{'USER'};
my $url = "http://wwwin.cisco.com/pcgi-bin/it/ice6/core/iceberg6/iceberg6_buildxml.cgi?agentid=$username";
my $tempfile = "/tmp/weekendberg-$username.xml";

# main loop
while ( "forever" ) {
	get_page();
	system('clear');
	parse_and_display();
	sleep($refresh_cycle);
}

#===  FUNCTION  ================================================================
#         NAME: get_page
#   PARAMETERS: none
#      RETURNS: none
#  DESCRIPTION: retrieves XML from iceberg
#       THROWS: no exceptions
#     COMMENTS: none
#     SEE ALSO: n/a
#===============================================================================
sub get_page {
	my $mech = WWW::Mechanize->new();
	eval { $mech->get($url); };

	#if tempfile exists, delete it first
	if (-e $tempfile) {
		unlink ($tempfile);
	}

	open (OUT, ">$tempfile");
	print OUT $mech->content;
	close(OUT);
} ## --- end sub get_page


#===  FUNCTION  ================================================================
#         NAME: parse_and_display
#   PARAMETERS: none
#      RETURNS: none
#  DESCRIPTION: Parses the XML from iceberg and displays the information
#       THROWS: no exceptions
#     COMMENTS: none
#     SEE ALSO: n/a
#===============================================================================
sub parse_and_display {
	#Create XML object and pull in the file
	my $simple = XML::Simple->new();
	my $tree = $simple->XMLin("$tempfile",ForceArray => 1);

	#undefine variables to reset for each loop
	undef %staffedskills;
	undef %talkingskills;
	undef %toasskills; #talking on another skill
	undef %idleskills;
	undef %readyskills;
	undef %grouped_staffed;
	undef %grouped_talking;
	undef %grouped_toas; #talkig on another skill
	undef %grouped_idle;
	undef %grouped_ready;
	undef %analyst_state;
	undef %analyst_time;
	undef %analyst_time_seconds;
	undef %analyst_toas;
	undef @analyst_talking;
	undef @analyst_idle;
	undef @analyst_ready;

	#get staffing count for talking agents
	foreach my $analyst (@{$tree->{agentstatus}->[0]->{talking}->[0]->{talkinganalyst}}) {
		my @skills = split /,/, $analyst->{callskills};
		foreach my $skill (@skills) {
			if ($staffedskills{$skill}) {
				$staffedskills{$skill} += 1;
			} else {
				$staffedskills{$skill} = 1;
			}
			$analyst_state{$analyst->{userid}} = "talking";
			$analyst_time{$analyst->{userid}} = $analyst->{statedate};
			$analyst_time_seconds{$analyst->{userid}} = 0;
			#convert HH:MM:SS to total seconds
			my $factor = 1;
			foreach my $segment ( reverse(split(/:/,$analyst->{statedate}) ) ) {
				$analyst_time_seconds{$analyst->{userid}} += $segment * $factor;
				$factor = $factor * 60;
			}
			# increment count if talking on another skill
			if ($skill ne $analyst->{talkingon}) {
				if ($toasskills{$skill}) {
					$toasskills{$skill} += 1;
				} else {
					$toasskills{$skill} = 1;
				}
			}
		}
		if ($talkingskills{$analyst->{talkingon}}) {
			$talkingskills{$analyst->{talkingon}} += 1;
		} else {
			$talkingskills{$analyst->{talkingon}} = 1;
		}
		#flag if not talking on Eng
		if ($analyst->{talkingon} !~ m/GTRC_ENG/) {
			$analyst_toas{$analyst->{userid}} = "true";
		}
	}

	#get staffing count for idle agents
	foreach my $analyst (@{$tree->{agentstatus}->[0]->{notready}->[0]->{notreadyanalyst}}) {
		my @skills = split /,/, $analyst->{callskills};
		foreach my $skill (@skills) {
			if ($staffedskills{$skill}) {
				$staffedskills{$skill} += 1;
			} else {
				$staffedskills{$skill} = 1;
			}
			if ($idleskills{$skill}) {
				$idleskills{$skill} += 1;
			} else {
				$idleskills{$skill} = 1;
			}
			$analyst_state{$analyst->{userid}} = "idle";
			$analyst_time{$analyst->{userid}} = $analyst->{statedate};
			$analyst_time_seconds{$analyst->{userid}} = 0;
			#convert HH:MM:SS to total seconds
			my $factor = 1;
			foreach my $segment ( reverse(split(/:/,$analyst->{statedate}) ) ) {
				$analyst_time_seconds{$analyst->{userid}} += $segment * $factor;
				$factor = $factor * 60;
			}
		}
	}

	#get staffing count for ready agents
	foreach my $analyst (@{$tree->{agentstatus}->[0]->{ready}->[0]->{readyanalyst}}) {
		my @skills = split /,/, $analyst->{callskills};
		foreach my $skill (@skills) {
			if ($staffedskills{$skill}) {
				$staffedskills{$skill} += 1;
			} else {
				$staffedskills{$skill} = 1;
			}
			if ($readyskills{$skill}) {
				$readyskills{$skill} += 1;
			} else {
				$readyskills{$skill} = 1;
			}
			$analyst_state{$analyst->{userid}} = "ready";
			$analyst_time{$analyst->{userid}} = $analyst->{statedate};
			$analyst_time_seconds{$analyst->{userid}} = 0;
			#convert HH:MM:SS to total seconds
			my $factor = 1;
			foreach my $segment ( reverse(split(/:/,$analyst->{statedate}) ) ) {
				$analyst_time_seconds{$analyst->{userid}} += $segment * $factor;
				$factor = $factor * 60;
			}
		}
	}

	#combine 1/2/3 skills into groups
	foreach my $skill (sort keys %staffedskills) {
		#set $group based on $skill
		switch ($skill) {
			case /GTRC_DESKTOP/ { $group=" DESKTOP"; }
			case /GTRC_ENG/ { $group=" ENG"; }
			case /GTRC_MAIN/ { $group=" MAIN"; }
			case /GTRC_MOBILITY/ { $group=" MOBILITY"; }
			case /GTRC_T2D_SPA/ { $group=" T2D_SPANISH"; }
			case /GTRC_T2D/ { $group=" T2D"; }
			case /GTRC_VIP/ { $group=" VIP"; }
			case /GTRC_WEBEX/ { $group=" WEBEX"; }
			case /GTRC_PORTUGUESE/ { $group=" PORTUGUESE"; }
			case /GTRC_SPANISH/ { $group=" SPANISH"; }
			case /GTRC_LWR/ { $group=" LWR"; }
			case /GTRC_DR_DESKTOP/ { $group=" DR_DESKTOP"; }
			case /GTRC_MAND_ENG/ { $group=" MANDARIN_ENG"; }
			case /GTRC_MAND/ { $group=" MANDARIN"; }
			case /GTRC_WARROOM/ { $group=" WARROOM"; }
			case /GTRC_CiscoTV/ { $group=" CiscoTV"; }
			case /GTRC_MAC/ { $group=" MAC"; }
			else	{ $group=$skill; }
		}

		#initialize $grouped_*{$group} hashes to zero if needed
		if (!defined($grouped_staffed{$group})) { $grouped_staffed{$group}=0; }
		if (!defined($grouped_talking{$group})) { $grouped_talking{$group}=0; }
		if (!defined($grouped_idle{$group})) { $grouped_idle{$group}=0; }
		if (!defined($grouped_ready{$group})) { $grouped_ready{$group}=0; }
		if (!defined($grouped_toas{$group})) { $grouped_toas{$group}=0; }

		#add to running total for $group
		$grouped_staffed{$group} += $staffedskills{$skill}; #staffedskills should never be null (famous last words)
		if ($talkingskills{$skill}) { $grouped_talking{$group} += $talkingskills{$skill}; }
		if ($idleskills{$skill}) { $grouped_idle{$group} += $idleskills{$skill}; }
		if ($readyskills{$skill}) { $grouped_ready{$group} += $readyskills{$skill}; }
		if ($toasskills{$skill}) { $grouped_toas{$group} += $toasskills{$skill}; }
	}

	#print out the grouped staffing numbers
	print "                Staff Avail  Idle  Talk (TOAS)\n";
	print "                ===== ===== ===== =============\n";
	foreach my $group (sort keys %grouped_staffed) {
		#if (!($group eq " ENG" || $group eq " T2D")) { next; }  #skip if not ENG or T2D
		printf ("%-14s %5d %5d %5d %5d",$group,$grouped_staffed{$group},$grouped_ready{$group},$grouped_idle{$group},$grouped_talking{$group});
		#only print TOAS if TOAS not zero
		if ($grouped_toas{$group} > 0) {
			printf ("  (%2d)\n",$grouped_toas{$group});
		} else {
			print "\n";
		}
	}

	#set alarm level if low/no staffing
	if ($grouped_staffed{' ENG'}) {
		if ($grouped_staffed{' ENG'} >= $eng_staffing_alert_threshold) {
			$eng_staffing = "GOOD";
		} else {
			$eng_staffing = "LOW";
		}
	} else {
		$eng_staffing = "UNSTAFFED";
	}	

	#print holding calls
	print "\n";
	print "Queue            Calls  Time\n";
	print "=====            =====  =====\n";
	$num_calls = 0;
	foreach my $queue (@{$tree->{queuestatus}->[0]->{queues}}) {
		printf("%-15s %5s %7s\n",$queue->{queuename},$queue->{queuenumber},$queue->{queuetime});
		$num_calls++;
	}
	if ($num_calls == 0) { print "No calls holding\n"; }


	print "\n";


	#3 column display of agents (Eng skill only)

	#gather agents into the three lists
	foreach my $analyst ( sort { $analyst_time_seconds{$b} <=> $analyst_time_seconds{$a} } keys %analyst_time_seconds ) {
		if ( $analyst_state{$analyst} eq "talking" ) {
			push (@analyst_talking, $analyst);
		} elsif ( $analyst_state{$analyst} eq "idle" ) {
			push (@analyst_idle, $analyst);
		} elsif ( $analyst_state{$analyst} eq "ready" ) {
			push (@analyst_ready, $analyst);
		}
	}
	
	#find the size of the longest list
	my $size = @analyst_talking;
	if ( scalar(@analyst_idle) > $size ) { $size = @analyst_idle; }
	if ( scalar(@analyst_ready) > $size ) { $size = @analyst_ready; }
	
	#print column headers
	print " TALKING               NOT READY             READY\n";
	print " =======               =========             =====\n";
	
	if ($eng_staffing eq "UNSTAFFED") {
		print "***No analysts with ENG skill logged in***\n";
	} else {
		#print the columns	
		for ($index = 0; $index < $size; $index++) {
			my $talking = $analyst_talking[$index];
			my $idle = $analyst_idle[$index];
			my $ready = $analyst_ready[$index];
			#print an * if not talking on ENG, else a space
			if ( $analyst_toas{$talking} eq "true") {
				print "*";
			} else {
				print " ";
			}
			printf("%-10s %8s | %-10s %8s | %-10s %8s\n",$talking,$analyst_time{$talking},$idle,$analyst_time{$idle},$ready,$analyst_time{$ready});
		}
	}


	if ($eng_staffing eq "LOW" || $eng_staffing eq "UNSTAFFED") {
		print "\a";
		print "\n***ALERT: Eng staffing is $eng_staffing***\n";
	}
} ## --- end sub parse_and_display
