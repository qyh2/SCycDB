#!/usr/bin/perl
use strict;
use List::Util qw(shuffle);
use Getopt::Long;

##Please specify where your prefered database searching tool locates
##NCBI blast ftp://ftp.ncbi.nlm.nih.gov/blast/executables/legacy.NOTSUPPORTED/2.2.26/blast-2.2.26-x64-linux.tar.gz
my $blast    = "~/bin/blast/bin/blastall";
my $formatdb = "~/bin/blast/bin/formatdb";
##diamond https://github.com/bbuchfink/diamond/releases
my $diamond = "~/bin/diamond-0.9.14/bin/diamond";
##usearch https://www.drive5.com/usearch/download.html
my $usearch = "~/bin/usearch8.1.1861_i86linux32";

my ( $workdir, $method, $outfile, $seqtype, $filetype, $sampleinfo, $randomsampling );
GetOptions(
  "d=s" => \$workdir,    ##set directory for sequence file location
  "m=s" => \$method,
  "f=s" => \$filetype,    ##file type, including fastq, fastq.gz, fasta,fasta.gz, fq, fq.gz, fa, fa.gz
  "s=s"  => \$seqtype,           ##prot, nucl
  "si=s" => \$sampleinfo,        ##information file for sequence numbers in each sample
  "rs=s" => \$randomsampling,    ##random sampling size, by default the minimum is used
);
if ( !defined $workdir
  || !defined $method
  || !defined $filetype
  || !defined $seqtype
  || !defined $sampleinfo
  || $method !~ /^diamond|usearch|blast$/
  || $filetype !~ /^fastq|fastq.gz|fasta|fasta.gz|fq|fq.gz|fa|fa.gz$/ )
{
  &PrintHelp();
  die;
}

my (@files);
if ( $method eq "diamond" ) {
   @files = glob("$workdir/*$filetype");
  my $diamond_db = "$diamond makedb --in data/SCycDB_2020Mar.faa --db data/SCycDB_2020Mar";
  system("$diamond_db");
  foreach my $file (@files) {
    my $out = $file;
    $out =~ s/$filetype/diamond/;
    system("$diamond blastx -k 1 -e 0.0001 -p 20 -d data/SCycDB_2020Mar -q $file -o $out")
      if $seqtype eq "nucl";
    system("$diamond blastp -k 1 -e 0.0001 -p 20 -d data/SCycDB_2020Mar -q $file -o $out")
      if $seqtype eq "prot";
    system("cp $out ./");
  }
}
elsif ( $method eq "usearch" ) {
  die "Please specify the location of usearch!" if !-e $usearch;
  if ( $filetype =~ /gz/ ) {
    die "Only fastq and fasta files are supported by usearch!\n";
  }
  @files = glob("$workdir/*$filetype");
  foreach my $file (@files) {
    my $out = $file;
    $out =~ s/$filetype/usearch/;
    system("$usearch -usearch_global $file -db data/SCycDB_2020Mar.faa -id 0.3 -blast6out $out");
    system("cp $out ./");
  }
}
elsif ( $method eq "blast" ) {
  die "Please specify the location of blast and/or formatdb!" if !-e $blast or !-e $formatdb;
  if ( $filetype =~ /gz|fastq/ ) {
    die "Only fasta files are supported by blast program!";
  }
  @files = glob("$workdir/*$filetype");
  system("$formatdb -i data/SCycDB_2020Mar.faa -p T");
  foreach my $file (@files) {
    my $out = $file;
    $out =~ s/$filetype/blast/;
    system("blastall -p blastp -d data/SCycDB_2020Mar.faa -i $file -o $out -m 8 -e 1e-4 -b 1 -v 1")
      if $seqtype eq "prot";
    system("blastall -p blastx -d data/SCycDB_2020Mar.faa -i $file -o $out -m 8 -e 1e-4 -b 1 -v 1")
      if $seqtype eq "nucl";
    system("cp $out ./");
  }
}

my %abundance;
my %samples;
my @sfiles=glob("*diamond") if $method eq "diamond";
@sfiles=glob("*usearch") if $method eq "usearch";
@sfiles=glob("*blast") if $method eq "blast";
die "No diamond/usearch/blast files were detected!\n" if $#sfiles==-1;
foreach my $sfile ( @sfiles ) {
  $sfile =~ /(.*?)\.$method/;
  my $sample = $1;
  $samples{$sample} = 1;
  my %hit;
  open( FILE, "$sfile" ) || die "#2\n";
  while (<FILE>) {
    chomp;
    my @items = split( "\t", $_ );
    my $gene = $id2gene{ $items[1] };
    if ( !$hit{ $items[0] } ) {
      $abundance{$sample}{$gene}++ if $gene;
      $hit{ $items[0] } = 1;
    }
  }
  close FILE;
  open(LIST,">$sample.list")||die"#2\n";
  foreach my $hit(keys %hit){
    print LIST "$hit\n";
  }
  close LIST;
  @files = glob("$workdir/*$filetype");
  foreach my $file (@files){  
    system("~/seqtk subseq $file $sample.list > $sample.SCyc.fastq");
 }
}

foreach my $file(glob("*.SCyc.fastq")){
  my $outfile=$file;
  my $reportfile=$file;
  $outfile=~s/SCyc.fastq/kraken2.txt/;
  $reportfile=~s/SCyc.fastq/kraken2.report/;
  system "~/kraken2/kraken2  --threads 60 --use-name --db ~/kraken2-fulldatabase $file --output $outfile --report $reportfile --use-mpa-style";
}

my %size;
my @sizes;
open( FILE, "$sampleinfo" ) || die "#3\n";
while (<FILE>) {
  chomp;
  my @items = split( "\t", $_ );
  $size{ $items[0] } = $items[1];
  push( @sizes, $items[1] );
}
close FILE;
foreach my $sample(keys %samples){
  die "$sample was not found in $sampleinfo, please check!\n" if !$size{$sample};
}

my %abundance;
foreach my $sample(keys %size){
  open(KRAKEN,"$sample\.kraken2.report")||die"#4\n";
  while(<KRAKEN>){
	chomp;
	my @items=split("\t",$_);
	if($items[0]=~/d__(Bacteria|Archaea)(.*?)\|p__([^\|]+)$/){
	  my $phylum=$3;
	  $abundance{"phylum"}{$sample}{$phylum}=$items[1];
	}
	if($items[0]=~/d__(Bacteria|Archaea)(.*?)\|c__([^\|]+)$/){
	  my $class=$3;
	  $abundance{"class"}{$sample}{$class}=$items[1];
	}
	if($items[0]=~/d__(Bacteria|Archaea)(.*?)\|o__([^\|]+)$/){
	  my $order=$3;
	  $abundance{"order"}{$sample}{$order}=$items[1];
	}
	if($items[0]=~/d__(Bacteria|Archaea)(.*?)\|f__([^\|]+)$/){
	  my $family=$3;
	  $abundance{"family"}{$sample}{$family}=$items[1];
	}
	if($items[0]=~/d__(Bacteria|Archaea)(.*?)\|g__([^\|]+)$/){
	  my $genus=$3;
	  $abundance{"genus"}{$sample}{$genus}=$items[1];
	}
	if($items[0]=~/d__(Bacteria|Archaea)(.*?)\|s__([^\|]+)$/){
	  my $species=$3;
	  $abundance{"species"}{$sample}{$species}=$items[1];
	}
  }
  close KRAKEN;
}

@sizes=sort{$a<=>$b}@sizes;
my $rs=$sizes[0];
my %abundance_rs;
foreach my $taxlevel(keys %abundance){
  %{$abundance_rs{$taxlevel}}=&RandomSampling(\%{$abundance{$taxlevel}},\%size,$rs);
}

my @samples = keys %size;
foreach my $taxlevel(keys %abundance_rs){
  open(OUT,">SCycDB_tax_$taxlevel.txt")||die"#5\n";
  print OUT "#random sampling: $rs\n";
  print OUT "Tax\t", join( "\t", @samples ), "\n";
  foreach my $tax ( sort keys %{$abundance_rs{$taxlevel}} ) {
	print OUT "$tax";
	foreach my $sample (@samples) {
	  print OUT "\t$abundance_rs{$taxlevel}{$tax}{$sample}" if $abundance_rs{$taxlevel}{$tax}{$sample};
	  print OUT "\t0"                          if !$abundance_rs{$taxlevel}{$tax}{$sample};
	}
	print OUT "\n";
  }
  close OUT;
}

sub RandomSampling() {
  my ( $abundance, $size, $rs ) = @_;
  my %abundance = %$abundance;
  my %size      = %$size;
  my %sum;
  foreach my $sample(keys %abundance){
	foreach my $gene(keys %{$abundance{$sample}}){
	  $sum{$sample}+=$abundance{$sample}{$gene};
	}
  }
  my %abundance_rs;
  foreach my $sample(keys %size){
	my @array=shuffle (1..$size{$sample});
	@array=@array[0..$rs-1];
	@array=grep{$_<=$sum{$sample}}@array;
	my $i=1;
	foreach my $gene(keys %{$abundance{$sample}}){
	  my @tmp=grep{$_>=$i && $_<=($abundance{$sample}{$gene}+$i-1)} @array;
	  $abundance_rs{$gene}{$sample}=@tmp;
	  $i=$abundance{$sample}{$gene}+1;
	}
  }   
  return %abundance_rs;
}

sub PrintHelp() {
  print "Incorrect parameters!\n";
  print
    "perl SCycDB_TaxonomyProfiler.pl -d <workdir> -m <diamond|usearch|blast> -f <filetype> -s <seqtype> -si <sample size info file> -rs <random sampling size>\n";
  print "-m diamond|usearch|blast\n";
  print "-f fastq, fastq.gz, fasta,fasta.gz, fq, fq.gz, fa, fa.gz\n";
  print "-s sequence type, nucl or prot \n";
  print "-si tab delimited file for sequence number in each file\n";
  print "-rs random sampling size\n";
}