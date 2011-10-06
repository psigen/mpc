package Driver;

# ************************************************************
# Description   : Generate dependencies for Make and NMake.
# Author        : Chad Elliott
# Create Date   : 3/21/2007
# $Id$
# ************************************************************

# ************************************************************
# Pragma Section
# ************************************************************

use strict;
use File::Basename;

use DependencyEditor;

# ************************************************************
# Data Section
# ************************************************************

my $version  = '1.2';
my $os       = ($^O eq 'MSWin32' ? 'Windows' : 'UNIX');
my %types;
my %defaults = ('UNIX'    => 'make',
                'Windows' => 'nmake',
               );

# ************************************************************
# Subroutine Section
# ************************************************************

sub BEGIN {
  my $fh = new FileHandle();
  my(%writers, %generators);

  ## Find all the dependency writers and object generators
  foreach my $dir (@INC) {
    if (opendir($fh, $dir)) {
      foreach my $module (readdir($fh)) {
        if ($module =~ /(.+)DependencyWriter\.pm$/) {
          my $type  = lc($1);
          my $class = $module;
          $class =~ s/\.pm$//;
          require $module;
          $writers{$type} = $class;
          $types{$type} = 1;
        }
        elsif ($module =~ /(.+)ObjectGenerator\.pm$/) {
          my $type  = lc($1);
          my $class = $module;
          $class =~ s/\.pm$//;
          require $module;
          $generators{$type} = $class;
        }
      }
      closedir($fh);
    }
  }

  ## Register them with the right factory
  DependencyWriterFactory::register(\%writers);
  ObjectGeneratorFactory::register(\%generators);
}


sub new {
  my $class = shift;
  my $self  = bless {'automatic' => [],
                    }, $class;

  foreach my $add (@_) {
    if ($add =~ /(UNIX|Windows)=(.*)/) {
      $defaults{$1} = $2;
    }
    elsif ($add =~ /automatic=(.*)/) {
      my @auto = split(/,/, $1);
      $self->{'automatic'} = \@auto;
    }
    else {
      print "WARNING: Unknown parameter: $add\n";
    }
  }

  return $self;
}


sub usageAndExit {
  my($self, $opt) = @_;
  my $base = basename($0);

  if (defined $opt) {
    print "$opt.\n";
  }

  print "$base v$version\n" .
        "Usage: $base [-D<MACRO>[=VALUE]] [-I<include dir>] ",
        (defined $self->{'automatic'}->[0] ? "[-A] " : ''),
        "[-R <VARNAME>]\n" .
        "       " . (" " x length($base)) .
        " [-e <file>] [-f <output file>] [-i] [-t <type>] [-n]\n" .
        "       " . (" " x length($base)) . " <files...>\n" .
        "\n";
  if (defined $self->{'automatic'}->[0]) {
    print "-A   Replace paths equal to the following variables with ",
          "the corresponding \$()\n     value: ",
          join(', ', @{$self->{'automatic'}}), ".\n";
  }
  print "-D   This option sets a macro to an optional value.\n" .
        "-I   The -I option adds an include directory.\n" .
        "-R   Replace \$VARNAME paths with \$(VARNAME).\n" .
        "-e   Exclude dependencies generated by <file>, but not <file> " .
        "itself.\n" .
        "-f   Specifies the output file.  This file will be edited if it " .
        "already\n     exists.\n" .
        "-i   Do not print an error if no source files are provided.\n" .
        "-n   Do not include inline files (ending in .i or .inl) in the " .
        "dependencies.\n" .
        "-t   Use specified type (";
  my @keys = sort keys %types;
  for(my $i = 0; $i <= $#keys; ++$i) {
    print "$keys[$i]" .
          ($i != $#keys ? $i == $#keys - 1 ? ' or ' : ', ' : '');;
  }
  print ") instead of the default.\n" .
        "     The default is ";
  @keys = sort keys %defaults;
  for(my $i = 0; $i <= $#keys; ++$i) {
    my $def = $keys[$i];
    print $defaults{$def} . " on $def" .
          ($i != $#keys ? $i == $#keys - 1 ? ' and ' : ', ' : '');
  }
  print ".\n";
  exit(0);
}


sub setReplace {
  my($self, $replace, $name, $value) = @_;

  if (defined $name) {
    ## The key will be used in a regular expression.
    ## So, we need to escape some special characters.
    $name = File::Spec->canonpath($name);
    $name =~ s/([\+\-\\\$\[\]\(\)\.])/\\$1/g;

    $$replace{$name} = $value;
  }
}


sub run {
  my($self, $args) = @_;
  my $argc    = scalar(@$args);
  my $type    = $defaults{$os};
  my $output  = '-';
  my $needsrc = 1;
  my($noinline, @files, %macros, @ipaths, %replace, %exclude);

  for(my $i = 0; $i < $argc; ++$i) {
    my $arg = $$args[$i];
    if ($arg =~ /^\-D(\w+)(=(.*))?/) {
      $macros{$1} = $3;
    }
    elsif ($arg =~ /^\-I(.*)/) {
      push(@ipaths, File::Spec->canonpath($1));
    }
    elsif ($arg eq '-A') {
      foreach my $auto (@{$self->{'automatic'}}) {
        $self->setReplace(\%replace, $ENV{$auto}, '$(' . $auto . ')');
      }
    }
    elsif ($arg eq '-R') {
      ++$i;
      $arg = $$args[$i];
      if (defined $arg) {
        my $val = $ENV{$arg};
        if (defined $val) {
          $self->setReplace(\%replace, $val, "\$($arg)");
        }
      }
      else {
        $self->usageAndExit('Invalid use of -R');
      }
    }
    elsif ($arg eq '-e') {
      ++$i;
      $arg = $$args[$i];
      if (defined $arg) {
        $exclude{$arg} = 1;
      }
      else {
        $self->usageAndExit('Invalid use of -e');
      }
    }
    elsif ($arg eq '-f') {
      ++$i;
      $arg = $$args[$i];
      if (defined $arg) {
        $output = $arg;
      }
      else {
        $self->usageAndExit('Invalid use of -f');
      }
    }
    elsif ($arg eq '-i') {
      $needsrc = undef;
    }
    elsif ($arg eq '-n') {
      $noinline = 1;
    }
    elsif ($arg eq '-h') {
      $self->usageAndExit();
    }
    elsif ($arg eq '-t') {
      ++$i;
      $arg = $$args[$i];
      if (defined $arg && defined $types{$arg}) {
        $type = $arg;
      }
      else {
        $self->usageAndExit('Invalid use of -t');
      }
    }
    elsif ($arg =~ /^[\-+]/) {
      ## We will ignore unknown options
      ## Some options for aCC start with +
    }
    else {
      push(@files, $arg);
    }
  }

  if (!defined $files[0]) {
    if ($needsrc) {
      $self->usageAndExit('No files specified');
    }
  }

  my $editor = new DependencyEditor();
  return $editor->process($output, $type, $noinline, \%macros,
                          \@ipaths, \%replace, \%exclude, \@files);
}
