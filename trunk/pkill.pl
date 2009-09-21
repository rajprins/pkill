#!/usr/bin/perl
# 
# A simple process viewer/killer for Linux, BSD and Solaris systems
# Note: requires Perl/Tk
#
# Copyright (c) 2005, Roy Prins


################################################################################
# uses and includes
################################################################################
use strict;
use warnings;
use Tk;  
use Tk::Font;
use Tk::PNG;


################################################################################
# Variables
################################################################################
my $OS            = $^O;
my $PS_OPTIONS;
my $REFRESHRATE   = 10000;
my $USERNAME      = getpwuid $<;
my $HEADER        = "USER | PID | COMMAND";
my $TITLE         = "\u$OS Process Killer";
my $SHOWALL       = 0;

my $mainwindow;
my $icon;
my $instructions;
my $frame0;
my $frame1;
my $frame2;
my $frame3;
my $frame4;
my $infoLabel;
my $filterField;
my $filterButton;
my $filtered = 0;
my $clearButton;
my $quitButton;
my $refreshButton;
my $toggleButton;
my $ps_options;
my @processes;
my $process;
my $process_list;
my $pid;
my $owner;
my $command;
my $horScrollbar;
my $vertScrollbar;
my $signal;
my @fields;
my $pidfield;
my $ownerfield;
my $commandfield;
my $counter;


################################################################################
# Subroutines
################################################################################

# check OS version in order to determine some OS specific settings
# For example, Windows is not supported....
sub checkOS {
   if ($OS eq "linux")  {
      # Linux
      $PS_OPTIONS = "aux";  
      $pidfield = 1;
      $ownerfield = 0;
      $commandfield = 10;
   }
   elsif ($OS eq "darwin") { 
      # Mac OS X/Darwin/OpenDarwin
      $PS_OPTIONS = "-auxc"; 
      $pidfield = 1;
      $ownerfield = 0;
      $commandfield = 10;
   }
   elsif ($OS eq "solaris") { 
      # Sun Solaris/OpenSolaris (but not Nexenta!)
      $PS_OPTIONS = '-e -o "user pid comm"'; 
      $pidfield = 1;
      $ownerfield = 0;
      $commandfield = 2;
   }
   else {
      printf("Sorry, $OS is not supported. Exiting....\n");
      exit 1;
   }
}

# called when a field in the listbox is double-clicked.
# PID is the first field in the listbox's active item.
# The signal to send the process is set by the radiobuttons and stored in $signal.
sub kill {
   $process = $process_list->get("active");
   (my $nothing, my $killpid) = split(/\ \|\ /, $process_list->get("active"));
   if ($killpid eq "1") {
      my $msg = "You cannot kill the init process!\n\nThis system depends on the init process. Killing it would result in a system failure.";
      $mainwindow->messageBox(-font=>"Ansi 9", -type=>"OK", -title=>"Error", -message=>$msg)
   }
   elsif ($nothing ne $USERNAME) {
      my $msg = "System error:\n\nYou cannot kill processes that are not yours.";
      $mainwindow->messageBox(-font=>"Ansi 9", -type=>"OK", -title=>"Error", -message=>$msg)
   }
   else {
      if ($killpid || $killpid ne "PID") {
         system("kill -s $signal $killpid");
         refresh_list();
      }
      else {
         my $msg = "System error:\n\nCannnot kill process $killpid using signal $signal.";
         $mainwindow->messageBox(-font=>"Ansi 9", -type=>"OK", -title=>"Error", -message=>$msg);         
      }
   }
}

# Switch views for showing only the current user's processes, or all processes
sub toggleAll {
   if ($SHOWALL == 0) {
      # show all processes
      $SHOWALL = 1;
      $toggleButton->configure(-text => "Current User");
   }
   else {
      # show procs of current user only
      $SHOWALL = 0;
      $toggleButton->configure(-text => "All Users");
   }
   refresh_list();
}

# Redraws the listbox with updated ps info
sub refresh_list{
   $process_list->delete(0, "end");
   getProcs();
}

# Get process info and store it in listbox
sub getProcs {
   # get the actual process list
   @processes = `ps $PS_OPTIONS`;

   # in "All users" mode, an extra header is generated. This fragment clears is out,
   # but only if the ps command returns more than one line. (due to the filter option)
   my $size = @processes; 
   if ($SHOWALL == 1 && $size > 1) {
         shift @processes;
   }   

   # header for columns
   $process_list->insert("0", $HEADER);
   $process_list->itemconfigure("0", -background=>"darkgrey");

   $counter = 0;
   
   # split output of the ps command and select the needed fields.
   # Linux and Mac OS X:
   # USER PID %CPU %MEM  VSZ RSS TTY STAT START TIME COMMAND
   # 0    1   2    3     4   5   6   7    8     9    10
   #
   # Solaris with custom options (-o "user pid comm"):
   # UID PID COMM
   # 0   1   2
   foreach my $process (@processes) {
      (@fields) = split(/\s+/, $process, ($commandfield+1));
      $owner    = $fields[$ownerfield];
      $pid      = $fields[$pidfield];
      $command  = $fields[$commandfield];
      
      # do not show processes that are not owned by current user if flag "-all" has not been set
      if ($SHOWALL == 0) {
            next unless($owner eq $USERNAME); 
      }
      
      $process_list->insert("end", "$owner | $pid | $command");
      
      # change the background color of every other line into blue   
      $counter++;
      if ($counter%2 != 0) {
         $process_list->itemconfigure($counter, -background=>"lightblue");
      }
      else {
         $process_list->itemconfigure($counter, -background=>"lightyellow");
      }
   }
}

# process search string, narrowing the process list
sub doFilter {
   my ($widget) = @_;
   my $filter = $widget->get();
   
   if (! $filter eq "") {
      # Check if the process list already has been filtered.
      # if so, first restore the orignal list in order to prevent filtering on filtering
      if ($filtered == 1) {
         $PS_OPTIONS = $ps_options;
      }
      
      # change the appearance of the button
      $filterButton->configure(-relief => "sunken"); 
      
      # backup of original options
      $ps_options = $PS_OPTIONS;
      
      # setting the new options
      $PS_OPTIONS = $PS_OPTIONS." | grep -i ".$filter." | grep -v grep";
      $filtered = 1;
      
      refresh_list;
   }
   else {
      refresh_list;
   }
}

# Undo the filtering on the ps command
sub clearFilter {
   #restore the original look of the filter button
   $filterButton->configure(-relief => "raised"); 
   
   $filterField->delete(0, 'end');
   # restore original search options
   $PS_OPTIONS = $ps_options;
   $filtered = 0;
   
   refresh_list;

}

# Check if a Perl icon is available. If so, include it in the window
sub checkResources {
   if (-e "perl.png") {
      $icon = $mainwindow->Photo(-file=>"perl.png", -format=>"PNG");
      $mainwindow->Icon(-image=>$icon);
   }
   elsif (-e "/usr/share/icons/perl.png") {
      $icon = $mainwindow->Photo(-file=>"/usr/share/icons/perl.png", -format=>"PNG");
      $mainwindow->Icon(-image=>$icon);
   }
   
}

################################################################################
### main logic
################################################################################

# First, check if the "-all" argument was given
if ((@ARGV != 0) && ($ARGV[0] eq "-a")) {
   $SHOWALL = 1;
}

# Next, check OS version, since not OSes are supported (eg. Windows)
checkOS;

# main window
$mainwindow = MainWindow->new(); 
$mainwindow->title($TITLE." (refresh rate: ".($REFRESHRATE/1000)." seconds)");
$mainwindow->resizable(0,0);

# check if the nice Perl icon is available
checkResources();

# change value of borderwidth into '2' for the "old skool" motif look or into '1' for a more modern look
$mainwindow->optionAdd("*BorderWidth"=>2);

# frame for holding help text
$instructions = "Instructions: Select a signal and then double-click on the process you wish to terminate.";
$frame0 = $mainwindow->Frame(-background=>"darkcyan", -relief=>"raised")->pack(-side=>"top", -fill=>"x");
$frame0->Label(-background=>"darkcyan", -foreground=>"white", -text=>$instructions)->pack();

# frame to hold radiobuttons for choosing a signal.
$frame1 = $mainwindow->Frame()->pack();
$frame1->Label(-text=>"Signal:")->pack(-side=>"left");

# default selection will be "Terminate" 
$signal = "TERM";
$frame1->Radiobutton(-variable=>\$signal, -text=> "Terminate", -value=>"TERM")->pack(-side=>"left");
$frame1->Radiobutton(-variable=>\$signal, -text=> "Stop",      -value=>"STOP")->pack(-side=>"left");
$frame1->Radiobutton(-variable=>\$signal, -text=> "Continue",  -value=>"CONT")->pack(-side=>"left");
$frame1->Radiobutton(-variable=>\$signal, -text=> "Interrupt", -value=>"INT")->pack(-side=>"left");
$frame1->Radiobutton(-variable=>\$signal, -text=> "Hangup",    -value=>"HUP")->pack(-side=>"left");
$frame1->Radiobutton(-variable=>\$signal, -text=> "Kill",      -value=>"KILL")->pack(-side=>"left");

# frame for process list
$frame2 = $mainwindow->Frame()->pack(-fill=>"both", -expand=>"y");

# extra frame for horizontal scrollbar
$frame4 = $mainwindow->Frame()->pack(-side=>"top", -fill=>"both", -expand=>"y");

#bottom frame for refresh button
$frame3        = $mainwindow->Frame()->pack(-fill=>"both", -expand=>"n");
$filterField   = $frame3->Entry()->pack(-side=>'left');
$filterButton  = $frame3->Button(-text=>"Filter", -command=>sub{doFilter($filterField)})->pack(-side=>'left');
$clearButton   = $frame3->Button(-text=>"Clear", -command=>sub{clearFilter()})->pack(-side=>"left");
$quitButton    = $frame3->Button(-text=>"Quit", -command=>\&exit)->pack(-side=>'right');
$refreshButton = $frame3->Button(-text=>"Refresh", -command=>\&refresh_list)->pack(-side=>'right');
$toggleButton  = $frame3->Button(-text=>"All Users", -command=>\&toggleAll)->pack(-side=>'right');

# create listbox and add to frame2
# note: this size actually determines the application size
$process_list = $frame2->Listbox(-height=>20)->pack(-side=>"left", -fill=>"both", -expand=>"y");

# get ps info and display selected fields in listbox
getProcs();

# bind a double-click on the listbox to the kill() subroutine.
$process_list->bind("<Double-1>", \&kill);

# create a vertical scrollbar for listbox (always present)
$horScrollbar = $frame4->Scrollbar(-orient=>"horizontal", -width=>10, -command=>["xview", $process_list], )->pack(-side=>"bottom", -fill=>"both");
$vertScrollbar = $frame2->Scrollbar(-orient=>"vertical", -width=>10, -command=>["yview", $process_list], )->pack(-side=>"right", -fill=>"y");
$process_list->configure(-xscrollcommand=>["set", $horScrollbar], -yscrollcommand=>["set", $vertScrollbar]);

# refresh the PS list every X seconds, where X is $REFRESHRATE
$process_list->repeat($REFRESHRATE,\&refresh_list);

MainLoop();

#EOF
