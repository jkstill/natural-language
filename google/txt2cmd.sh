#!/usr/bin/env bash

set -u

: << 'THE-GOAL'

The end goal is to transform this sentence:

  'add 2 1 gig datafiles to the data tablespace'

Into this command:

   alter tablespace data add datafile size 1G;

This command should be run twice.

THE-GOAL

: << 'ORDEROPS'

To create this command, we need to know a few things

- what type of action is being taken (add )
- what is the subject of the action (datafile)
- what type of entity the action is to be performed on (tablespace)
- the name of the entity (data)
- is there a size of datafile? (yes)
- how many times to run the command(2)

ORDEROPS

###############################################
# objects we know how to manipulate
# only tablespace is implemented at this time

declare -a recognizedObjects=(tablespace table index)


###############################################
# temp files
nlaJSONFile=$(mktemp -u --suffix .json)
echo "nlaJSONFile: $nlaJSONFile"

csvRequestFile=$(mktemp -u --suffix .csv)
echo "csvRequestFile: $csvRequestFile"

###############################################
# control vars
declare VERBOSE
: ${VERBOSE:=0}
echo "VERBOSE: $VERBOSE"

declare showCallStack
: ${showCallStack:=0}
echo "showCallStack: $showCallStack"

###############################################
# setup file descriptors
# set stack FD to 1 for stdout, 2 for stderr
# setting the warnFDNummber to 1 though will cause calls to functions to fail, as 
# return values are via 'echo'

declare warnFDNumber=2
declare warnFD 
exec {warnFD}>&$warnFDNumber

declare stackFDNumber=1
declare stackFD
exec {stackFD}>&$stackFDNumber

printCallStack () {
	[[ $showCallStack -gt 0 ]] && {
		echo >&$stackFD
		echo "   Call Stack:" >&$stackFD
		for i in ${!FUNCNAME[@]}
		do
			[[ $i -eq 0 ]] && { continue; }

			echo "     ${FUNCNAME[$i]}"  >&$stackFD
			:
		done
	}
}

verbose () {

	local msgStr="$@"

	local nameBanner="########## f: ${FUNCNAME[1]} #################"
	local prefix='### '
	local postBanner="##############################################"

	[[ $VERBOSE -lt 1 ]] && {
		: # do nothing
		return
	}

	echo  >&$warnFD
	echo $nameBanner >&$warnFD
	echo $prefix $msgStr >&$warnFD

	echo  >&$warnFD

	# when called from within verbose, always set the call stack channel to 2
	# otherwise functions will fail when output is returned via echo
	exec {stackFD}>&$warnFD
	printCallStack
	exec {stackFD}>&$stackFDNumber

	echo  >&$warnFD
	echo $postBanner >&$warnFD
	echo  >&$warnFD

}

declare -A fields=(
	[label]=1 
	[tag]=2
	[value]=3
	[lemma]=4
	[offset]=5
)

#echo ${fields[offset]}


declare -a data

loadData () {
	local i=0
	while read line
	do
		data[$i]="$line"
		(( i++ ))
		# we do not need the quotes
	done < <(tr -d '"' < $csvRequestFile) # comma match "
}

# pass label and tag
# only works for 1 occurrence of a value
getLemma () {
	local label=$1;shift
	local tag=$1;shift

	verbose "label: $label"
	verbose "tag: $tag"

	local matched=0
	for line in ${data[@]}
	do
		# faster with built in regex, but no time to figure that out right now
		clabel="$(echo $line | cut -f${fields[label]} -d,)"
		ctag="$(echo $line | cut -f${fields[tag]} -d,)"
		verbose  "  line: $line"
		verbose "  clabel: $clabel"
		verbose "  ctag: $ctag"
		#if [ \( "$clabel"=="$label" \) -a \( "$ctag"=="$tag" \) ]; then

		if [ \( "$clabel" == "$label" \) -a \( "$ctag" == "$tag" \) ]; then
			matched=1
			break
		fi
	done

	if [[ $matched -ne 0 ]]; then
		echo $line | cut -f${fields[lemma]} -d,
	else
		echo ''
	fi
		
}

# pass label, tag and value
getLemmaPos () {
	local label=$1;shift
	local tag=$1;shift
	# if more than 1 matching line, then this is a bug
	# rushed PoC, what can I say...
	local searchLemma=$1;shift

	verbose "label: $label"
	verbose "tag: $tag"

	local matched=0
	local clabel
	local ctab
	local clemma
	local cpos=-1

	for line in ${data[@]}
	do
		# faster with built in regex, but no time to figure that out right now
		clabel="$(echo $line | cut -f${fields[label]} -d,)"
		ctag="$(echo $line | cut -f${fields[tag]} -d,)"
		clemma="$(echo $line | cut -f${fields[lemma]} -d,)"
		verbose  "  line: $line"
		verbose "  clabel: $clabel"
		verbose "  ctag: $ctag"
		verbose "  clemma: $clemma"

		if [ \( "$clabel" == "$label" \) -a \( "$ctag" == "$tag" \) -a \( "$clemma" == "$searchLemma" \) ]; then
			cpos="$(echo $line | cut -f${fields[offset]} -d,)"
			break
		fi
	done

	echo $cpos
		
}

# stuff multiple lines of the same label and tag into an array
getTagLines () {
	local label=$1;shift
	local tag=$1;shift
	declare -n arrayRef=$1;shift

	verbose "getTagLines label: $label"
	verbose "getTagLines tag: $tag"

	local i=0

	for line in ${data[@]}
	do
		# faster with built in regex, but no time to figure that out right now
		clabel="$(echo $line | cut -f${fields[label]} -d,)"
		ctag="$(echo $line | cut -f${fields[tag]} -d,)"
		verbose "  getTagLines line: $line"
		verbose "  getTagLines clabel: $clabel"
		verbose "  getTagLines ctag: $ctag"
		#if [ \( "$clabel"=="$label" \) -a \( "$ctag"=="$tag" \) ]; then
		if [ \( "$clabel" == "$label" \) -a \( "$ctag" == "$tag" \) ]; then
			verbose "getTagLines: $line"
			arrayRef[$i]=$line
			(( i++ ))
		fi
	done

}

getTypeCount () {
	local label=$1;shift
	local tag=$1;shift

	verbose "label: $label"
	verbose "tag: $tag"
	local count=0


	# note: Find out the difference between NUM NUM and NUMBER NUM

	for line in ${data[@]}
	do
		# faster with built in regex, but no time to figure that out right now
		clabel="$(echo $line | cut -f${fields[label]} -d,)"
		ctag="$(echo $line | cut -f${fields[tag]} -d,)"

		if [ \( "$clabel" == "$label" \) -a \( "$ctag" == "$tag" \) ]; then

			(( count++ ))
		fi
	done

	echo $count
}

# root and verb
getAction () {
	local action="$(getLemma ROOT VERB)"
	[[ -z $action ]] && { action="$(getLemma ROOT NOUN)"; }
	
	local raction

	case $action in
		increase|add) raction=alter;;
		remove) raction=drop;;
		disable) raction=stop;;
		*) raction=UNKNOWN;;
	esac
	
	[[ $raction == 'UNKNOWN' ]] && {
		echo
		echo UNKNOWN in getAction
		echo 
		echo "action: $action"
		printCallStack
		echo
		exit 1
	}

	echo $raction
}

getPrepObj () {
	getLemma POBJ NOUN
}


# verify data
for i in ${!data[@]}
do
	echo $i: ${data[$i]}
	:
done

buildTbsCmd () {
	local cmd="$(getAction)"
	# we already know this is a tablespace
	cmd="$cmd tablespace "

	#local t="$(getPrepObj)"
	#cmd="$cmd $t"


	#echo "cmd 1: $cmd"
	# we need that verb again, but not as alter, but as 'add'

	# WIP - calling it a day on this - enough for a demo
	# this works with the built in demo statement
	# fails with 'increase data tablespace by 20 gig'
	# a proper parser is needed


	local objAction="$(getLemma ROOT VERB)"
	cmd="$cmd $objAction"
	local subObj

	case $objAction in
		add) subObj="$(getLemma DOBJ NOUN)";;
		*) subObj=UNKNOWN;;
	esac

	[[ $subObj == 'UNKNOWN' ]] && {
		echo
		echo UNKNOWN in buildTbsCmd
		echo
		echo "cmd: $cmd"
		echo "objAction: $objAction"
		echo 
		printCallStack
		echo
		exit 1
	}

	cmd="$cmd $subObj"

	#getClosestNoun DOBJ NOUN $subObj

	# there may be a size for the as well as the number of times to perform 
	# look for NUMBER NUM
	# looking for 0, 1 or 2 numbers

	# NUM,NUM is the unit size of the datafile
	# NUMBER,NUM is the number of operations
	# NN,NOUN in  this case is the number of datafiles to add

	local datafileSize="$(getLemma NUM NUM)"
	local numOfOps="$(getLemma NUMBER NUM)"

	# this needs to be the NN NOUN closest to unit
	# there may be 2+ NN NOUNs
	# WIP - START HERE
	local datafileUnit="$(getLemma NN NOUN)"

	local sizeClause=''

	if [[ $datafileSize == '' ]]; then
		sizeClause=''
	else
		sizeClause="size $datafileSize $datafileUnit"
	fi

	cmd="$cmd $sizeClause"

	echo cmd: $cmd

}

getAbsVal () {
	local int=$1

	if [[ $int -lt 0 ]]; then
		(( int *= -1 ))
	fi

	echo $int
}

getClosestNoun () {
	local label=$1;shift
	local tag=$1;shift
	local searchLemma=$1;shift

	declare -a nouns
	local smallestGap=9999999
	local smallestGapPos

	local nounPos="$(getLemmaPos $label $tag $searchLemma)"
	verbose "getClosestNoun nounPos: $nounPos"

	getTagLines NN NOUN nouns

	if [[ ${#nouns[@]} -gt 0 ]]; then
		for i in ${!nouns[@]}
		do
			#echo i: $i
			verbose "nounLine: " ${nouns[$i]}
			# this 'cut' needs to be a function
			local nnPos="$(echo ${nouns[$i]} | cut -f${fields[offset]} -d,)"
			verbose "   nnPos: $nnPos"

			local gap
			(( gap = $nounPos - $nnPos ))
			gap="$(getAbsVal $gap)"

			[[ $gap -le $smallestGap ]] && { smallestGapPos=$i ; }

		done
	fi

	# not checking for undef, etc - this would be (is) a bug in real code
	
	local smallestGapLine=${nouns[$smallestGapPos]} 

	#echo "smallestGapLine: $smallestGapLine"

	echo $smallestGapLine | cut -f${fields[lemma]} -d,

}

# stub
buildIndexCmd () {
	echo "stub for buildIndexCmd"
}


# stub
buildTableCmd () {
	echo "stub for buildTableCmd"
}

getTargetObj () {

	local targetObj=''

	for line in ${data[@]}
	do
		# faster with built in regex, but no time to figure that out right now
		local lemma="$(echo $line | cut -f${fields[lemma]} -d,)"
		verbose "  lemma: $lemma"
		for objType in "${recognizedObjects[@]}"
		do
			[[ $lemma == $objType ]] && {
				targetObj="$objType"
				break
			}
		done
	done

	echo "$targetObj"

}

buildCmd () {

	loadData

	# find out what we are working on - tablespace, table, ...

	local targetObj="$(getTargetObj)"

	local cmd2run

	case $targetObj in 
		tablespace) cmd2run=buildTbsCmd;;
		table) cmd2run=buildTableCmd;;
		index) cmd2run=buildIndexCmd;;
		*) cmd2run=UNKNOWN;;
	esac

	[[ $cmd2run == 'UNKNOWN' ]] && {
		echo
		echo UNKNOWN in buildcmd
		echo prepObj: $prepObj
		printCallStack
		echo
		exit 1
	}

	 eval "$cmd2run"

}

cleanup () {
	rm -f $nlaJSONFile 
	rm -f $csvRequestFile
}



# demo command
# echo "written command: 'add 2 1 gig datafiles to the data tablespace'"

nlCMD="$@"
: ${nlCMD:='add 2 1 gig datafiles to the data tablespace'}

cat <<-EOF

working on this English statement: "$nlCMD"

EOF

gcloud ml language analyze-syntax --content="$nlCMD" > $nlaJSONFile

# just for diplay
jq ' .tokens | .[] | (.dependencyEdge.label + " - " +.partOfSpeech.tag + " - " + .text.content + " - " + .lemma + " - " + (.text.beginOffset|tostring) ) '  < $nlaJSONFile

# create CSV for the script functions to use
jq --sort-keys -r ' .tokens | .[] | [.dependencyEdge["label"], .partOfSpeech["tag"], .text["content"], .lemma, .text["beginOffset"] ] | @csv '  < $nlaJSONFile  | sort -n -t, -k 5 > $csvRequestFile


buildCmd
#loadData
#getAction

cleanup



