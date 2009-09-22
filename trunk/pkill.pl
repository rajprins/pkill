#!/usr/bin/perl
# 
# A simple process viewer/killer for Linux, BSD and Solaris systems
# Note: requires Perl/Tk
#
# Copyright (c) 2005, Roy Prins
#
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#     * Redistributions of source code must retain the above copyright
#       notice, this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above copyright
#       notice, this list of conditions and the following disclaimer in the
#       documentation and/or other materials provided with the distribution.
#     * Neither the name of the <organization> nor the
#       names of its contributors may be used to endorse or promote products
#       derived from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY <copyright holder> ''AS IS'' AND ANY
# EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL <copyright holder> BE LIABLE FOR ANY
# DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
# ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


################################################################################
# uses and includes
################################################################################
use strict;
use warnings;
use Tk;  
use Tk::Font;
use Tk::PNG;


################################################################################
# Constants & Variables
################################################################################
my $OS          = $^O;
my $REFRESHRATE = 30; #seconds
my $USERNAME    = getpwuid $<;
my $HEADER      = "USER | PID | COMMAND";
my $TITLE       = "\u$OS Process Killer";
my $ICON        = "camel.png";

my $ps_args;
my $ps_args_bak;
my $showAll;
my $filtered;
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
my $clearButton;
my $quitButton;
my $refreshButton;
my $toggleButton;
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

# Perform some basic initialization
sub init {
   # by default, the process list is not filtered
   $filtered = 0;
   
   # check if the "-all" argument was given
   if ((@ARGV != 0) && ($ARGV[0] eq "-a")) {
      $showAll = 1;
   }
   else {
      $showAll = 0;   
   }
}


# check OS version in order to determine some OS specific settings
# For example, Windows is not supported....
sub checkOS {
   if ($OS eq "linux")  {
      # Linux
      $ps_args = "aux";  
      $pidfield = 1;
      $ownerfield = 0;
      $commandfield = 10;
   }
   elsif ($OS eq "darwin") { 
      # Mac OS X/Darwin/OpenDarwin
      $ps_args = "-auxc"; 
      $pidfield = 1;
      $ownerfield = 0;
      $commandfield = 10;
   }
   elsif ($OS eq "solaris") { 
      # Sun Solaris/OpenSolaris (but not Nexenta!)
      $ps_args = '-e -o "user pid comm"'; 
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
# The signal to send the process is set by the radiobuttons and stored in $signal
sub kill {
   $process = $process_list->get("active");
   (my $nothing, my $killpid) = split(/\ \|\ /, $process_list->get("active"));
   if ($killpid eq "1") {
      my $msg = "Cannot kill the init process!\n\nThis system depends on the init process. Killing it would result in a system failure.";
      $mainwindow->messageBox(-background=>"red", -font=>"Ansi 9", -type=>"OK", -title=>"Error", -message=>$msg)
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
# Note that it's not allowed to kill processes not belonging to the current user
sub toggleAll {
   if ($showAll == 0) {
      # show all processes
      $showAll = 1;
      $toggleButton->configure(-text => "Current User");
   }
   else {
      # show procs of current user only
      $showAll = 0;
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
   @processes = `ps $ps_args`;

   # in "All users" mode, an extra header is generated. This fragment clears is out,
   # but only if the ps command returns more than one line. (due to the filter option)
   my $size = @processes; 
   if ($showAll == 1 && $size > 1) {
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
      if ($showAll == 0) {
            next unless($owner eq $USERNAME); 
      }
      
      # add process info to list
      $process_list->insert("end", "$owner | $pid | $command");
      
      $counter++;
      # change the background color of every other line into blue...         
      if ($counter%2 != 0) {
         $process_list->itemconfigure($counter, -background=>"lightblue");
      }
      # ...or yellow
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
         # safe to assume that $ps_args_bak has been set
         $ps_args = $ps_args_bak;
      }
      
      # change the appearance of the button
      $filterButton->configure(-relief => "sunken"); 
      
      # backup of original options
      $ps_args_bak = $ps_args;
      
      # setting the new options
      $ps_args = $ps_args." | grep -i ".$filter." | grep -v grep";
      $filtered = 1;
      
      refresh_list;
   }
   else {
      #print "No filter string defined.\n";
   }
}

# Undo the filtering on the ps command
sub clearFilter {
   if ($filtered == 1) {
      #restore the original look of the filter button
      $filterButton->configure(-relief => "raised"); 
   
      $filterField->delete(0, 'end');
      # restore original search options
      $ps_args = $ps_args_bak;
      $filtered = 0;
   
      refresh_list;
   }
   else {
      #print "No filter defined. No sense in clearing...\n";
   }

}

sub setMainWindow {
   $mainwindow = MainWindow->new();  
   #$mainwindow->configure(-width=>"10", -height=>"10");
   $mainwindow->title($TITLE." (refresh rate: ".$REFRESHRATE." seconds)");
   # Window is not resizable
   $mainwindow->resizable(0,0);
   # change value of borderwidth into '2' for the "old skool" motif look or into '1' for a more modern look
   $mainwindow->optionAdd("*BorderWidth"=>2);
   
   # Check if a Perl icon is available. If so, include it in the window
   if (-e $ICON) {
      $icon = $mainwindow->Photo(-file=>$ICON, -format=>"PNG");
      $mainwindow->Icon(-image=>$icon);
   }
   elsif (-e "/usr/share/icons/$ICON") {
      $icon = $mainwindow->Photo(-file=>"/usr/share/icons/$ICON", -format=>"PNG");
      $mainwindow->Icon(-image=>$icon);
   }
   
}

sub setLayout {
   # Frame0: frame for holding help text
   $instructions = "Instructions: Select a signal and then double-click on the process you wish to terminate.";
   $frame0 = $mainwindow->Frame(-background=>"darkcyan", -relief=>"raised")->pack(-side=>"top", -fill=>"both");
   $frame0->Label(-background=>"darkcyan", -foreground=>"white", -text=>$instructions)->pack();
   
   # Frame1: frame to hold radiobuttons for choosing a signal. Default selected is "Terminate"
   $signal = "TERM";
   $frame1 = $mainwindow->Frame()->pack();
   $frame1->Label(-text=>"Signal:")->pack(-side=>"left");
   $frame1->Radiobutton(-variable=>\$signal, -text=> "Terminate", -value=>"TERM")->pack(-side=>"left");
   $frame1->Radiobutton(-variable=>\$signal, -text=> "Stop", -value=>"STOP")->pack(-side=>"left");
   $frame1->Radiobutton(-variable=>\$signal, -text=> "Continue", -value=>"CONT")->pack(-side=>"left");
   $frame1->Radiobutton(-variable=>\$signal, -text=> "Interrupt", -value=>"INT")->pack(-side=>"left");
   $frame1->Radiobutton(-variable=>\$signal, -text=> "Hangup", -value=>"HUP")->pack(-side=>"left");
   $frame1->Radiobutton(-variable=>\$signal, -text=> "Kill", -value=>"KILL")->pack(-side=>"left");
   
   # Frame2: frame for process list
   # note: size of listbox actually determines the application size
   $frame2 = $mainwindow->Frame()->pack(-fill=>"both", -expand=>"y");
   $process_list = $frame2->Listbox(-height=>20)->pack(-side=>"left", -fill=>"both", -expand=>"y");
   $vertScrollbar = $frame2->Scrollbar(-orient=>"vertical", -width=>10, -command=>["yview", $process_list], )->pack(-side=>"right", -fill=>"y");
   # bind a double-click on the listbox to the kill() subroutine.
   $process_list->bind("<Double-1>", \&kill);
   
   # Frame3: extra frame for horizontal scrollbar
   $frame3 = $mainwindow->Frame()->pack(-side=>"top", -fill=>"both", -expand=>"y");
   $horScrollbar = $frame3->Scrollbar(-orient=>"horizontal", -width=>10, -command=>["xview", $process_list], )->pack(-side=>"bottom", -fill=>"both");
   
   # bind scrollbars to process list
   $process_list->configure(-xscrollcommand=>["set", $horScrollbar], -yscrollcommand=>["set", $vertScrollbar]);
   
   # Frame4: bottom frame for function buttons
   $frame4 = $mainwindow->Frame()->pack(-fill=>"both", -expand=>"n");
   #$filterField = $frame4->Entry()->pack(-side=>'left');
   $filterField = $frame4->Entry(-borderwidth=>"1", -highlightbackground=>"grey", -highlightcolor=>"grey")->pack(-side=>'left');
   
   $filterButton = $frame4->Button(-text=>"Filter", -command=>sub{doFilter($filterField)})->pack(-side=>'left');
   $clearButton = $frame4->Button(-text=>"Clear", -command=>sub{clearFilter()})->pack(-side=>"left");
   $quitButton = $frame4->Button(-text=>"Quit", -command=>\&exit)->pack(-side=>'right');
   $refreshButton = $frame4->Button(-text=>"Refresh", -command=>\&refresh_list)->pack(-side=>'right');
   $toggleButton = $frame4->Button(-text=>"All Users", -command=>\&toggleAll)->pack(-side=>'right');
}


sub setContent {
   # get process info and display selected fields in listbox
   getProcs();

   # refresh the processlist list every X seconds, where X is $REFRESHRATE * 1000
   $process_list->repeat(($REFRESHRATE*1000),\&refresh_list);   
}


################################################################################
### main logic
################################################################################
init;
checkOS;
setMainWindow;
setLayout;
setContent;

MainLoop();
#EOF
