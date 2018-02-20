#!/user/bin/perl
# this version normalises first

use warnings;
use strict;
use Spreadsheet::ParseExcel;

# collect the Sample names and build the data back line by line
my $readdir = &promptUser("Enter the main directory");
my $rtrange = &promptUser("Enter your threshold");
my $standard = &promptUser("Enter your standard(s) name; use \"\|\" (pipe) if more than one");
my $standard_range = &promptUser("Enter your standard's estimated rt range;i.e. 20-22");
my $outputfile = &promptUser("Enter your output file name");

unless ("$readdir and $rtrange and $outputfile") {
	die "Need all input parameters to run!\n";
}

opendir (DIR1, $readdir) or die "$!";

my @number_of_files;
my (@rtmins, @rtminimum, @rtmaximum, @no_same_rt, @hitnames, @onefiledata, @areas_per_sample, @areas_total); # create data containers
my $sample_name;

#sort directories
my @directories;
while (my $subdir_pre = readdir(DIR1)) {
	unless ($subdir_pre !~ /^\.+/){
		next;
	}
	push @directories, $subdir_pre;
}
close(DIR1);

my @sorted_directories = sort @directories;

print "--this is the order of your files:--\n";

#collect all standard peaks
my @standard_box;

#collect samples that don't have standards
my $deathcheck = 0;
my $dienumber = 0;
my @deathbox;

# obtain the RT means for all samples:
foreach my $subdir(@sorted_directories){
	# stores the subdirectories name as sample names.
	$sample_name = $subdir;
	push @number_of_files, $sample_name;

	&grabrtexcel;	

	if ($deathcheck > 0){
		print "\*\*$sample_name has no standard!\*\*\n";
		push @deathbox, "$sample_name\n";
		$deathcheck = 0;
		$dienumber++;
	}else {
		print "$sample_name\n";
	}
}

#kill program if there are samples with no standards:
if ($dienumber > 0){
	open (MYOUTFILE3, ">$outputfile.err");
	print MYOUTFILE3 "\n\n\*\*OOPS! $dienumber sample(s) doesn't have standards!\nThey are:\n@deathbox\nUnable to continue...\*\*\n";
	print MYOUTFILE3 "paramters used:\nStandard's name: $standard\nStandard's rt range = $standard_range\n";
	die "\n\n\*\*OOPS! $dienumber sample(s) doesn't have standards!\nThey are:\n@deathbox\nUnable to continue...\*\*\n";
	close (MYOUTFILE3);
}

#check if all samples have a standard:
unless (scalar(@standard_box) == scalar(@sorted_directories)){
	die "the number of standards found per sample does not tally!\n";
}

#normalize the standards based on the first one found:
my @standard_table;
my ($first_standard,$first_rows) = split ("\t",$standard_box[0]);
for (my $aa = 0; $aa < scalar(@standard_box); $aa++){
	my ($rt_std,$rows_std) = split ("\t",$standard_box[$aa]);
	my $difference = $first_standard-$rt_std;
	my $rounded_diff = sprintf("%.3f",$difference);
	my $adding_std = "$standard_box[$aa]\t$rounded_diff";
	$standard_box[$aa]=$adding_std;
	for (my $q = 0; $q < $rows_std; $q++){
		push @standard_table, $rounded_diff;
	}
}

#print out the normalization table:
open (MYOUTFILE2, ">$outputfile.norm.table");
print MYOUTFILE2 "Standard's name: $standard\n";
print MYOUTFILE2 "Sample_Name\tOriginal_rt\tNumber_compounds\tNormalization_value\n";
for (my $bb = 0; $bb < scalar(@standard_box); $bb++){
	print MYOUTFILE2 "$number_of_files[$bb]\t$standard_box[$bb]\n";
}
close (MYOUTFILE2);

#check if all data have a standard:
unless (scalar(@standard_table) == scalar(@onefiledata)){
	die "the number of standards found per sample does not tally!\n";
}

#reappend & adjust onefiledata:
my @new_onefiledata;
for (my $w = 0; $w < scalar(@standard_table); $w++){
	my ($aiyo_rt, $aiyo_hit) = split("\t",$onefiledata[$w]);
	my $aiyo_rt_adj = $aiyo_rt+$standard_table[$w];
	push @new_onefiledata, "$aiyo_rt_adj\t$aiyo_hit";
}

# sort the data according to rt
print "--now sorting your mess...don't mind the gibberish--\n";
my @sorted_onedata = sort {$a <=> $b} @new_onefiledata;
my (@temparray_rt, @temparray_hit);

print "\n--Ahh.. what a relief... onward!--\n";
for (my $j = 0; $j < scalar(@sorted_onedata); $j++){
	unless (@temparray_rt) {
		($temparray_rt[0],$temparray_hit[0]) = split("\t",$sorted_onedata[$j]);
		next;
	}
	my ($rtmins_curr, $hitnames_curr) = split("\t",$sorted_onedata[$j]);
	my $rtmins_prev = $temparray_rt[0];
	my $rtmin_max = $rtmins_prev+$rtrange*2;
	if ($rtmin_max>=$rtmins_curr){
		push @temparray_rt, $rtmins_curr;
		push @temparray_hit, $hitnames_curr;
	} else {
		my $rtmin_total;
		my $total_temprt = scalar(@temparray_rt);
		if ($total_temprt == 1){
			$rtmin_total = $temparray_rt[0];
		}else {
			$rtmin_total = eval join '+', @temparray_rt;
		}
		my $rtmin_mean = $rtmin_total/$total_temprt;
		my $hitname_total= join("/",@temparray_hit);
		push @rtmins, sprintf("%.3f",$rtmin_mean);
		push @rtminimum, $temparray_rt[0];
		push @rtmaximum, $temparray_rt[$total_temprt-1];
		push @hitnames, $hitname_total;
		push @no_same_rt, $total_temprt;
		undef @temparray_rt;
		undef @temparray_hit;
	}
}

#count duplicates and remove redundancies in hitnames:
my @hitnames_nr;
foreach my $hit_line(@hitnames){
	my @hittypes = split("/",$hit_line);
	my @results;	
	my %hash;
	foreach my $hithash(@hittypes){
		$hash{$hithash}++;
}
	foreach my $hithash_2(sort {$hash{$b} <=> $hash{$a}} keys %hash){
		push @results, "$hash{$hithash_2}:$hithash_2";
	}
	my $joinedresults = join ("/",@results);
	push @hitnames_nr, $joinedresults;
}

print "--halfway there!--\n";
my $countdown = scalar (@number_of_files);

# now to look for the area scores:
for (my $d = 0; $d < scalar(@sorted_directories); $d++){
	$sample_name = $sorted_directories[$d];

	&grabareaexcel;

	my ($standard_num,$rows_num,$standard_info) = split ("\t",$standard_box[$d]);

	for (my $z = 0; $z < scalar(@rtmins); $z++){
		&runthruarray_ar ($rtminimum[$z],$rtmaximum[$z],$standard_info);
	}
	
	for (my $k = 0; $k < scalar(@rtmins); $k++){
		if ($areas_total[$k]) {
			my $new_area = "$areas_total[$k]\t$areas_per_sample[$k]";
			$areas_total[$k]=$new_area;
		} else {
			$areas_total[$k]=$areas_per_sample[$k];
		}
	}	
	undef(@areas_per_sample);
	$countdown--;
	print "--$countdown samples more--\n";
}

# output:
open (MYOUTFILE1, ">$outputfile");
my $sampleheaders = join("\t",@number_of_files);
print MYOUTFILE1 "#rt_range = +/- $rtrange\n";
print MYOUTFILE1 "rt_mean\trt_min\trt_max\tno_same_rt\thitnames\t$sampleheaders\n"; 
for (my $i = 0; $i < scalar(@rtmins); $i++){
	print MYOUTFILE1 "$rtmins[$i]\t$rtminimum[$i]\t$rtmaximum[$i]\t$no_same_rt[$i]\t$hitnames_nr[$i]\t$areas_total[$i]\n";
}
close (MYOUTFILE1);

print "--Phew, all done!--\n";


sub grabrtexcel {
	my $excelfile = "$readdir\\$sample_name\\MSRep.xls";
	my $parser = Spreadsheet::ParseExcel->new();
	my $workbook = $parser->parse($excelfile);
	
	die $parser->error(), ".\n" if ( !defined $workbook );

	my $worksheet = $workbook->worksheet('LibRes');
	my ($row_min, $row_max) = $worksheet->row_range();
	my $number_rows = 0;
	my @standard_hits;
	for my $row ( 9 .. $row_max ) {
		my $cell = $worksheet->get_cell( $row, 0 );
		next unless $cell;
		my $rtmin = ($worksheet->get_cell( $row, 1 )) -> unformatted();
	
		#some hits many not have a hitname!
		my $dahit;
		my $hitname = ($worksheet->get_cell( $row, 8 ));
		if ($hitname){
		 	$dahit = $hitname -> unformatted();
		} else {
			$dahit = "NO_HIT";
		}
		push @onefiledata, "$rtmin\t$dahit";
		
		#collect standard:
		if ($dahit =~ m/$standard/i) {
			my ($std_dahit_min,$std_dahit_max)=split("-",$standard_range);
			if ($std_dahit_min<=$rtmin && $std_dahit_max>=$rtmin ){
				#print "gotta hit!\n"; #debug;
				push @standard_hits, $rtmin;
			}
		}
		$number_rows++;
	}

	unless ($standard_hits[0]) {
		$deathcheck++;
		return;
		#die "\*\*the sample above doesn't have the standard! Unable to continue...\*\*\n";
	}

	my $standard_total;
	if (scalar(@standard_hits) == 1) {
		$standard_total = $standard_hits[0];
	} else {
		$standard_total = eval join '+', @standard_hits;
	}
	my $standard_mean = $standard_total/(scalar(@standard_hits));
	my $round_standard_mean = sprintf("%.3f",$standard_mean);
		push @standard_box, "$round_standard_mean\t$number_rows";
	
}


sub grabareaexcel {
	undef(@onefiledata); #clear data container
	my $excelfile = "$readdir\\$sample_name\\MSRep.xls";
	my $parser = Spreadsheet::ParseExcel->new();
	my $workbook = $parser->parse($excelfile);
	
	die $parser->error(), ".\n" if ( !defined $workbook );

	my $worksheet = $workbook->worksheet('LibRes');
	my ( $row_min, $row_max ) = $worksheet->row_range();

	for my $row ( 9 .. $row_max ) {
		my $cell = $worksheet->get_cell( $row, 0 );
		next unless $cell;
		my $rtmin = ($worksheet->get_cell( $row, 1 )) -> unformatted();
		my $area = ($worksheet->get_cell( $row, 3 )) -> unformatted();
		push @onefiledata, "$rtmin\t$area";
	}
}


sub runthruarray_ar {
	my ($rtmin_min,$rtmin_max,$standard_info) = ($_[0],$_[1],$_[2]);
	my $counter = "nope";
	my $all_area;
	my @area_fill;
	foreach my $onefile(@onefiledata) {
		my ($rtmin, $area) = split ("\t",$onefile);
		my $rtmin_adj = $rtmin+$standard_info;
		my $round_rtmin_1 = sprintf("%.3f",$rtmin_adj);
		if ($rtmin_min<=$round_rtmin_1 && $rtmin_max>=$round_rtmin_1 ){	
			push @area_fill, $area;
			$counter = "have";		
		}
	}
	if ($counter=~/nope/){
		push @areas_per_sample, "NA";
	} elsif ($counter=~/have/){
		#$all_area = join("/",@area_fill); #debug
		if (scalar(@area_fill) == 1){
			$all_area = $area_fill[0];
		}else {
			$all_area = eval join '+', @area_fill;
		}
		push @areas_per_sample,$all_area;
	}
}


sub promptUser {   
	my ($promptString) = @_;
      print $promptString, ": ";
   $_ = <STDIN>;
   chomp;
      return $_;
}

## written by: Joel Low Zi-Bin 20130410
