#!/usr/bin/perl
use strict;
use warnings;

# Known bug: resizing the window when not viewing the help page causes the
# gui to croak when you do view the help page. Not quite sure how to fix this,
# yet.

use Prima;
use Prima::Buttons;
use Prima::Notebooks;
use Prima::ScrollWidget;
use Prima::Application;
use Prima::InputLine;
use Prima::Edit;
use Prima::PodView;
use Prima::FileDialog;
use Carp;
use File::Spec;
use FindBin;

# Load PDL if they have it
my $loaded_PDL;
BEGIN {
	$loaded_PDL = 0;
	eval {
		require PDL;
		PDL->import;
		require PDL::NiceSlice;
		$loaded_PDL = 1;
	};
	print $@ if $@;
}

my $app_filename = File::Spec->catfile($FindBin::Bin, $FindBin::Script);

##########################
# Initialize the history #
##########################
my @history;
my $current_line = 0;
my $last_line = 0;

if (-f 'prima-repl.history') {
	open my $fh, '<', 'prima-repl.history';
	while (<$fh>) {
		chomp;
		push @history, $_;
	}
	close $fh;
}
# Set the current and last line to the end of the history:
$current_line = $last_line = @history;

# Save the last 200 lines in the history file:
END {
	open my $fh, '>', 'prima-repl.history';
	# Only store the last 200:
	my $offset = 0;
	$offset = @history - 200 if (@history > 200);
	while ($offset < @history) {
		print $fh $history[$offset++], "\n";
	}
	close $fh;
}

# A very handy function that I use throughout, but which needs to be defined
# later.
sub goto_page;



my $padding = 10;
my $window = Prima::MainWindow->new(
	pack => { fill => 'both', expand => 1, padx => $padding, pady => $padding },
	text => 'Prima REPL',
	size => [600, 600], 
);
	# Add a notbook with output and help tabs:
	my $notebook = $window->insert(TabbedScrollNotebook =>
		pack => { fill => 'both', expand => 1, padx => $padding, pady => $padding },
		tabs => ['Output', 'Help'],
		style => tns::Simple,
	);
		my $output = $notebook->insert_to_page(0, Edit =>
			pack => { fill => 'both', expand => 1, padx => $padding, pady => $padding },
			text => '',
			cursorWrap => 1,
			wordWrap => 1,
			readOnly => 1,
			backColor => cl::LightGray,
		);
		# Over-ride the defaults for these:
		$output->accelTable->insert([
			  ['', '', km::Ctrl | kb::PageUp,	\&goto_prev_page	]	# previous
			, ['', '', km::Ctrl | kb::PageDown,	\&goto_next_page	]	# next
		], '', 0);

		my $pod = $notebook->insert_to_page(1, PodView =>
			pack => { fill => 'both', expand => 1, padx => $padding, pady => $padding },
		);
#		$pod->load_file($app_filename);

		
	# Add the eval line:
	my $inline = $window->insert( InputLine =>
		text => '',
		pack => {fill => 'both', after => $notebook, padx => $padding, pady => $padding},
		accelItems => [
			# Enter runs the line
			  ['', '', kb::Return, \&pressed_enter]
			, ['', '', kb::Enter, \&pressed_enter]
			# Ctrl-Shift-Enter runs and goes to the output window
			, ['', '', kb::Return | km::Ctrl | km::Shift,	sub{pressed_enter(); goto_page 0}	]
			, ['', '', kb::Enter  | km::Ctrl | km::Shift,	sub{pressed_enter(); goto_page 0}	]
			# Navigation scrolls through the command history
			, ['', '', kb::Up, sub {set_new_line($current_line - 1)}]
			, ['', '', kb::Down, sub {set_new_line($current_line + 1)}]
			, ['', '', kb::PageUp, sub {set_new_line($current_line - 10)}]
			, ['', '', kb::PageDown, sub {set_new_line($current_line + 10)}]
			# Ctrl-i selects the default widget (the editor for edit tabs)
			, ['', '', km::Ctrl | ord 'i', sub {goto_page $notebook->pageIndex}]
		],
	);
	# give it the focus at the start
	$inline->select;

# A dialog box that will be used for opening and saving files:
my $open_dialog = Prima::OpenDialog-> new(
	filter => [
		['Perl scripts' => '*.pl'],
		['PDL modules' => '*.pdl'],
		['Perl modules' => '*.pm'],
		['POD documents' => '*.pod'],
		['All' => '*']
	]
);


# The list of default widgets for each page. Help and output default to
# the evaluation line:
my @default_widget_for = ($inline, $inline);

sub goto_page {
	my $page = shift;
	$page = 0 if $page >= $notebook->pageCount;
	$page = $notebook->pageCount - 1 if $page == -1;
	# Make sure the page exists (problems could arrise using Alt-9, for example)
	if ($page < $notebook->pageCount) {
		$notebook->pageIndex($page);
		$default_widget_for[$page]->select;
	}
}

sub goto_next_page {
	goto_page $notebook->pageIndex + 1;
}
sub goto_prev_page {
	goto_page $notebook->pageIndex - 1;
}

# Add some accelerator keys to the window for easier navigaton:
$window->accelItems([
	  ['', '', km::Ctrl | ord 'i',	sub {$inline->select}	]	# input line
	, ['', '', km::Alt  | ord '1',		sub {goto_page 0}	]	# output page
	, ['', '', km::Ctrl | ord 'h',		sub {goto_page 1}	]	# help
	, ['', '', km::Alt  | ord '2',		sub {goto_page 1}	]	# help (page 2)
	, ['', '', km::Alt  | ord '3',		sub {goto_page 2}	]	# page 3
	, ['', '', km::Alt  | ord '4',		sub {goto_page 3}	]	# .
	, ['', '', km::Alt  | ord '5',		sub {goto_page 4}	]	# .
	, ['', '', km::Alt  | ord '6',		sub {goto_page 5}	]	# .
	, ['', '', km::Alt  | ord '7',		sub {goto_page 6}	]	# .
	, ['', '', km::Alt  | ord '8',		sub {goto_page 7}	]	# .
	, ['', '', km::Alt  | ord '9',		sub {goto_page 8}	]	# page 8
	, ['', '', km::Ctrl | kb::PageUp,	\&goto_prev_page	]	# previous
	, ['', '', km::Ctrl | kb::PageDown,	\&goto_next_page	]	# next
	, ['', '', km::Ctrl | ord 'n',		sub {new_file()}	]	# new tab
	, ['', '', km::Ctrl | ord 'w',		sub {close_file()}	]	# close tab
	, ['', '', km::Ctrl | ord 'o',		sub {open_file()}	]	# open file
	, ['', '', km::Ctrl | ord 'S',		sub {save_file()}	]	# save file
]);

sub new_help {
	
}

# Creates a new text-editor tab and selects it
sub new_file {
	my $page_no = $notebook->pageCount;
	my $name = shift || '';
	# Add the tab number to the name:
	$name .= ', ' if $name;
	$name .= '#' . ($page_no + 1);

	my @tabs = @{$notebook->tabs};
	$notebook->tabs([@tabs, $name]);
	my $page_widget = $notebook->insert_to_page(-1, Edit =>
			text => '',
			pack => { fill => 'both', expand => 1, padx => $padding, pady => $padding },
			# Allow for insertions, deletions, and newlines:
			tabIndent => 1,
			syntaxHilite => 1,
			wantTabs => 1,
			wantReturns => 1,
			wordWrap => 0,
			autoIndent => 1,
			cursorWrap => 1,
		);

	# Update the accelerators.
	my $accTable = $page_widget->accelTable;

	# Allow Ctrl Enter to execute:
	$accTable->insert([
		  ['', '', kb::Return 	| km::Ctrl | km::Shift,	sub{run_file(); goto_page 0}	]
		, ['', '', kb::Enter  	| km::Ctrl | km::Shift,	sub{run_file(); goto_page 0}	]
		, ['', '', kb::Return 	| km::Ctrl,  sub{run_file()}				]
		, ['', '', kb::Enter  	| km::Ctrl,  sub{run_file()}				]
		, ['', '', kb::PageUp 	| km::Ctrl,  \&goto_prev_page				]
		, ['', '', kb::PageDown | km::Ctrl,  \&goto_next_page				]
		], '', 0);

	# Make the editor the default widget for this page.
	push @default_widget_for, $page_widget;
	
	# Go to this page:
	goto_page -1;
}

# closes the tab number, or name if provided, or current if none is supplied
sub close_file {
	# Get the desired tab; default to current tab:
	my $to_close = shift || $notebook->pageIndex + 1;	# user counts from 1
	my @tabs = @{$notebook->tabs};
	if ($to_close =~ /^\d+$/) {
		$to_close--;	# correct user's offset by 1
		$to_close += $notebook->pageCount if $to_close < 0;
		# Check that a valid value is used:
		if ($to_close == 0) {
			print "You cannot remove the output tab\n";
			goto_page 0;
			return;
		}
		elsif ($to_close == 1) {
			print "You cannot remove the Help tab\n";
			goto_page 0;
			return;
		}
		
		# Close the tab
		carp ("Not checking if the file needs to be saved. This should be fixed.");
		$notebook->{notebook}->delete_page($to_close);
		splice @tabs, $to_close, 1;
		splice @default_widget_for, $to_close, 1;
	}
	else {
		# Provided a name. Close all the tags with the given name:
		my $i = 2;
		$to_close = qr/$to_close/ unless ref($to_close) eq 'Regex';
		while ($i < @tabs) {
			if ($tabs[$i] eq $to_close) {
				carp ("Not checking if the file needs to be saved. This should be fixed.");
				$notebook->{notebook}->delete_page($_);
				splice @default_widget_for, $i, 1;
				splice @tabs, $i, 1;
				redo;
			}
			$i++;
		}
	}
	
	# Update the tab numbering:
	$tabs[$_-1] =~ s/\d+$/$_/ for (3..@tabs);
	
	# Finally, set the new, final names and select the default widget:
	$notebook->tabs(\@tabs);
	$default_widget_for[$notebook->pageIndex]->select;
}

# Opens a file (optional first argument, or uses a dialog box) and imports it
# into the current tab, or a new tab if they're at the output or help tabs:
sub open_file {
	my ($file) = @_;
	my $page = $notebook->pageIndex;
	
	# Get the filename with a dialog if they didn't specify one:
	if (not $file) {
		# Return if they cancel out:
		return unless $open_dialog->execute;
		# Otherwise load the file:
		$file = $open_dialog->fileName;
	}
	
	# Extract the name and create a tab:
	(undef,undef,my $name) = File::Spec->splitpath( $file );
	if ($page < 2) {
		new_file ($name);
	}
	else {
		name($name);
	}
	
	carp("** Need to check the contents of the current tab before overwriting");
	
	# Load the contents of the file into the tab:
    open( my $fh, $file ) or return print "Couldn't open $file";
    my $text = do { local( $/ ) ; <$fh> } ;
    # Note that the default widget will always be an Edit object because if the
    # current tab was not an Edit object, a new tab will have been created and
    # selected.
    $default_widget_for[$notebook->pageIndex]->textRef(\$text);
}

# A file-opening function for initialization scripts
sub init_file {
	new_file;
	open_file @_;
}

sub save_file {
	my $page = $notebook->pageIndex;
	if ($page < 2) {
		print "Go to the tab with the contents you want to save before calling this";
		goto_page 0;
		return;
	}
	
	# Get the filename as an argument or from a save-as dialog. This would work
	# better if it got instance data for the filename from the tab itself, but
	# that would require subclassing the editor, which I have not yet tried.
	my $filename = shift;
	unless ($filename) {
		my $save_dialog = Prima::SaveDialog-> new(
			filter => [
				['Perl scripts' => '*.pl'],
				['PDL modules' => '*.pdl'],
				['Perl modules' => '*.pm'],
				['POD documents' => '*.pod'],
				['All' => '*']
			]
		);
		# Return if they cancel out:
		return unless $save_dialog->execute;
		# Otherwise get the filename:
		$filename = $save_dialog->fileName;
	}
	
	# Open the file and save everything to it:
	open my $fh, '>', $filename;
	my $textRef = $default_widget_for[$notebook->pageIndex]->textRef;
	print $fh $$textRef;
	close $fh;
}

# A function to run the contents of a multiline environment
sub run_file {
	my $page = shift || $notebook->pageIndex + 1;
	$page--;	# user starts counting at 1, not 0
	croak("Can't run output page!") if $page == 0;
	croak("Can't run help page!") if $page == 1;
	
	# Get the text from the multiline and run it:
	my $text = $default_widget_for[$page]->text;
	# Process the text with NiceSlice if they try to use it:
	if ($text =~ /use PDL::NiceSlice/) {
		if ($loaded_PDL) {
			$text = PDL::NiceSlice->perldlpp($text);
		}
		else {
			print "PDL did not load properly, so I can't apply NiceSlice to your code.";
			print "Don't be surprised if you get errors...";
		}
	}

	no strict;
	eval $text;
	use strict;

	# If error, switch to the console and print it to the output:
	if ($@) {
		my $tabs = $notebook->tabs;
		my $header = "----- Error running ", $tabs->[$page], " -----";
		print $header;
		print $@;
		print '-' x length $header;
		$@ = '';
		goto_page 0;
	}
}

# Change the name of a tab
sub name {
	my $name = shift;
	my $page = shift || $notebook->pageIndex + 1;
	my $tabs = $notebook->tabs;
	$tabs->[$page - 1] = "$name, #$page";
	$notebook->tabs($tabs);
}

# Changes the contents of the evaluation line to the one stored in the history:
sub set_new_line {
	my $requested_line = shift;
	
	# Save changes to the current line in history:
	$history[$current_line] = $inline->text;
	
	# make sure the requested line makes sense:
	$requested_line = 0 if $requested_line < 0;
	$requested_line = $last_line if $requested_line > $last_line;
	
	$current_line = $requested_line;
	
	# Load the text:
	$inline->text($history[$requested_line]);
	
	# Put the cursor at the end of the line:
	$inline->charOffset(length $history[$requested_line]);
}


# Evaluates the text in the input line
my $lexicals_allowed = 0;
my $current_help_topic;
sub pressed_enter {
	# They pressed return. First save the contents. If they typed this on the
	# help page, append 'help' to it:
	my $in_text = $inline->text;
	
	$in_text = "help $in_text"
		if ($notebook->pageIndex == 1 and $in_text !~ /^(help|exit)/);

	# If the user made an error, I will want to go back into the history and
	# comment out the line, so keep track of it:
	my $old_current_line = $current_line;
	
	# print this line:
	print "> $in_text";

	# Add this line to the current line of the history, if the current line is
	# not the last line:
	$history[$current_line] = $in_text if $current_line != $last_line;
	# Add this line to the last line of the history if it's not a repeat:
	if (@history == 0 or $history[$last_line - 1] ne $in_text) {
		$history[$last_line] = $in_text ;
		$last_line++;
	}
	
	# Remove the text from the entry
	$inline->text('');
	
	# Set the current line to the last one:
	$current_line = $last_line;
	
	# Check for the help command. If they just type 'help', show them the
	# documentation for this application:
	if ($in_text eq 'help' or $in_text eq 'help help') {
		$pod->load_file($app_filename);
		goto_page 1;
	}
	# If they want help for a specific module, show that:
	elsif ($in_text =~ /^help/) {
		# Select the help tab
		goto_page 1;
		
		# If they specified a module, open its pod
		if ($in_text =~ /^help\s+(.+)/) {
			my $module = $1;
			print "Opening the documentation for $module";
			$pod->load_file($module);
		}
	}
	elsif ($in_text =~ /^pdldoc\s+(.+)/) {
		print `pdldoc $1`;
	}
	else {
		# A command to be eval'd. Lexical variables don't work, so croak if I
		# see one. This could probably be handled better.
		if ($in_text =~ /my/ and not $lexicals_allowed) {
			$@ = join("\n", "Lexical variables not allowed in the line evaluator"
					, 'because you cannot get to them after the current line.'
					, 'To allow lexicals, say $lexicals_allowed = 1');
		}
		else {
			no strict;
			$in_text = PDL::NiceSlice->perldlpp($in_text) if ($loaded_PDL);
			my_eval($in_text);
		}
	
		# If error, print that to the output
		if ($@) {
			print $@;
			# Add comment hashes to the beginning of the erroneous lines:
			$in_text = "#$in_text";
			$history[$old_current_line] = $in_text;
			$history[$last_line - 1] = $in_text;
			$@ = '';
			goto_page 0;
		}
	}
}

sub my_eval {
	my $to_run = shift;
	no strict;
	eval $to_run;
	use strict;

=for later
	# working here
	# fork and run
	my $pid = fork;
	if ($pid) {
		# parent here. close the writing filehandle:
		close $writeme;
		$writeme = undef
		
		# set a timer function to check for info back from the process.
		
	}
	elsif (defined $pid and not $pid) {
		# child; run the eval and return control:
		close $readme;
		
		eval $to_run;
		# Send a notification that we're all done:
		allow_input();
		close $readme;
		# always end child processes with an exit:
		exit;
	}
	else {
		# pipe error; just eval the code and make the process wait:
		($readme, $writeme) = ();
		eval $to_run;
		$inline->enabled(1);
	}

=cut

}

# A function called from eval'd code and/or the child process that tells the
# parent that it can re-enable input. This 
#sub allow_input

################################
# Output handling and mangling #
################################

# Set autoflush on stdout:
$|++;

# Convenience function for PDL folks.
sub p {	print @_ }

# convenience function for clearing the output:
my $output_line_number = 0;
sub clear {
	$output->text('');
	$output_line_number = 0;
}

# Useful function to simulate user input (so it gets saved in the history)
sub simulate_run {
    my $command = shift;
    # Get the current content of the inline:
    my $old_text = $inline->text;
    # Set the content to the new command:
    $inline->text($command);
    # run it:
    pressed_enter();
    # put the original content back on the inline:
    $inline->text($old_text);
}

# Here is a utility function to print to the output window. Both standard output
# and standard error are later tied to printing to this interface, so you can
# just use 'print' in all your code and it'll go to this.

sub outwindow {
	# Join the arguments and split them at the newlines:
	my @lines = split /\n/, join('', @_);
	# Remove some weird/annoying error messages:
	s/ \(eval \d+\)// for @lines;
	# Add the lines and keep track of the output line number:
	$output->insert_line($output_line_number, @lines);
	$output_line_number += @lines;
	
	# Add the lines to the logfile
	open my $logfile, '>>', 'prima-repl.logfile';
	print $logfile $_, "\n" foreach @lines;
	close $logfile;
	
	# I'm not super-enthused with manually putting the cursor at the end of
	# the text, or with forcing the scrolling. I'd like to have some way to
	# determine if the text was already at the bottom, in which case I would
	# continue scrolling, if it was not, I would not scroll. But, I cannot find
	# how to do that at the moment, so it'll just force scroll with every
	# printout. working here:
	$output->cursor_cend;
}

# Redirect standard output using this filehandle tie. Thanks to 
# http://stackoverflow.com/questions/387702/how-can-i-hook-into-perls-print
# for this one.
package IO::OutWindow;
use base 'Tie::Handle';
use Symbol qw<geniosym>;
sub TIEHANDLE { return bless geniosym, __PACKAGE__ }

our $OLD_STDOUT;
sub PRINT {
    shift;
    no strict 'refs';
    main::outwindow(@_)
}

sub PRINTF {
	shift;
	my $to_print = sprintf(@_);
    no strict 'refs';
	main::outwindow(@_);
}

tie *PRINTOUT, 'IO::OutWindow';
# Redirect standard output and standard error to the PDL console:
$OLD_STDOUT = select( *PRINTOUT );
*STDERR = \*PRINTOUT;

package main;

eval 'require PDL::Version' if not defined $PDL::Version::VERSION;

# Print the opening message:
print "Welcome to the Prima REPL.";
print "Using PDL version $PDL::Version::VERSION" if ($loaded_PDL);
print ' ';
print "If you don't know what you're doing, check out the help tab";
print "by typing 'help' and pressing Enter, or by pressing Ctrl-h or Alt-2";
print "or Ctrl-PageDown, or by clicking on the help tab with your mouse.";

#################################
# Run any initialization script #
#################################
if (-f 'prima-repl.initrc') {
	print "Running initialization script";
	do 'prima-repl.initrc';
}

run Prima;

__END__

=head1 Prima::REPL Help

This is the help documentation for  Prima::REPL, a graphical run-eval-print-loop
(REPL) for perl development, targeted at pdl users. Its focus is on L<PDL>, the
Perl Data Language, but it works just fine even if you don't have PDL.

Prima::REPL provides a tabbed environment with an output tab, a help tab, and
arbitrarily many file tabs. It also provides a single entry line at the bottom
of the window for direct command entry.

At this point, some links to further documentation would be appropriate, as well
as a tutorial.

In keeping with the text-based L<pdl> command provided with L<PDL>, this REPL
doesn't do the I<print> part, but I'll get to that in just a little bit.

This documentation is written assuming you have C<pdl-gui> installed on your
system and are reading it from the Help tab. You could also be reading this
from CPAN or L<perldoc>, but I will be giving many interactive examples and
would encourage you to install and run C<pdl-gui> so you can follow along. Note
you do not need L<PDL> installed to run C<pdl-gui>.

=head1 Fixing Documentation Fonts

If your documentation fonts look bad, you can change them by typing a command,
but I have not yet figured that out. Sorry.

 # need command here

=head1 Tutorial

First, you'll want to have an easy way to get back to this document when you
need help. To do that, simply type 'help' in the evaluation line at the bottom
of the screen. You can look at the pod documentation for any file in the help
tab by putting the module or file name after the help command, but typing help
by itself will always give you this document.

Go back to the output tab and type the following in the evaluation line:

 print "Hello, world!"

=head1 pdldoc

The following will print the results of a pdldoc command-line search to the
output window. The quotes are required:

 pdldoc 'command'

I may end up parsing the results of this command, opening the pod, and scrolling
to the specific location, but I've not figured it out yet.

=head1 PDL Debugging

To get PDL debugging statements, type the following in the evaluation line:

 $PDL::debug = 1

=head1 Navigation

=over

=item Ctrl-i

When you are viewing the Output or Help tabs, this key combination selects the
evaluation line. When you are in an edit tab, this key combination toggles
between the entry line and the text editor.

=item Alt-1, ..., Alt-9

Selects the tab with the associated number.

=back

=head1 Ideas

Provide a general interface for tab-specific command processing. That way,
help tabs can look at the command entry and if it just looks like a module,
it'll load the documentation. Otherwise it will pass the command on to the
normal command processing functionality. New tabs (via plugins) could then
provide new commands. (The difference between commands and plain-old functons
should be stressed somehow. Functions operate through simple evaluate, whereas
commands are pulled out and parsed. These concepts need to be cleaned up.)
