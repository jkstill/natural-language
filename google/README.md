
Experimenting with Naturally Language Analysis for Oracle Commands
=================================================================

New authentication requirements:

see [Set Billing Project](https://cloud.google.com/docs/authentication/rest#set-billing-project)

files:
* request.json
* request.sh


Terms:

- NL: natural language
- NLA: natural language analysis
- ML: machine learning

Try out some NLA on English sentences to modify an oracle database 

# Add Space to a tablescae

written command: 'add 2 1 gig datafiles to the data tablespace'

## Analyze with google NLA

gcloud command:

```text
$ gcloud ml language analyze-syntax --content='add 2 1 gig datafiles to the data tablespace > t1.json'

$  wc t1.json
 238  432 5964 t1.json

```

Get the full sentence that was issued:

```text
$  jq '.sentences | .[0] | .text | .content'  < t1.json
"add 2 1 gig datafiles to the data tablespace"
```

Now get the parts of the sentence:

```text
>  jq ' .tokens | .[] |  (.dependencyEdge.label + " - " +.partOfSpeech.tag + " - " + .text.content ) '  < t1.json
"ROOT - VERB - add"
"NUMBER - NUM - 2"
"NUM - NUM - 1"
"NN - NOUN - gig"
"DOBJ - NOUN - datafiles"
"PREP - ADP - to"
"DET - DET - the"
"NN - NOUN - data"
"POBJ - NOUN - tablespace"

```

The explanations for both Lables and Tags are here:

[ML NL Tokens](https://cloud.google.com/natural-language/docs/reference/rest/v1/Token)

## Building a Command

It would help this process if you can remember English grammar, and all the parts of a sentence.

Sadly, I do not recall much(most) of the finer points of grammar rules.

However, it appears the documentation provides a means to determine how to change this speech into a command.

Assumpion: Database files are on ASM, or if on an OS filesystem, using OMF.

The target command: `alter tablespace test add datafile size 1g`

As the request is for two files, the command should be executed twice. Probably this could be done in 1 command, but I am trying to keep this simple.

The ROOT of the sentence is 'add'. So, we need to modify something, by adding something else to it.

The preposition is 'to'.

The 'what' in this case is signified by POBJ (object of prepositoin) - a tablespace.

Which in this case is NN value of 'data'.

The problem here is there are two nn values:  'gig' and 'data'

How to know which one to use with the 'data' tablespace?

One way may be to find the NN that is both prior to the POBJ and closest.

We can determine this from the offset of the field. 

Add offset to jq:

```text
$ jq ' .tokens | .[] | (.dependencyEdge.label + " - " +.partOfSpeech.tag + " - " + .text.content + " - " + .lemma + " - " + (.text.beginOffset|tostring) ) '  < t1.json
"ROOT - VERB - add - add - 0"
"NUMBER - NUM - 2 - 2 - 4"
"NUM - NUM - 1 - 1 - 6"
"NN - NOUN - gig - gig - 8"
"DOBJ - NOUN - datafiles - datafile - 12"
"PREP - ADP - to - to - 22"
"DET - DET - the - the - 25"
"NN - NOUN - data - data - 29"
"POBJ - NOUN - tablespace - tablespace - 34"
```

Note the use of the 'tostring' modifier.  jq will throw an error otherwise, ' string ("ROOT - VER...) and number (0) cannot be added'

So far the JSON is transformed for readability.

Now it will be converted to simpler JSON for consumption.

This following syntax is not exactly intutive, but does make some sense once you learn a little jq.

```
jq ' .tokens | .[] | {"label": .dependencyEdge["label"], "tag": .partOfSpeech["tag"], "value": .text["content"], "lemma": .lemma, "offset": .text["beginOffset"]} '  t1.json
{
  "label": "ROOT",
  "tag": "VERB",
  "value": "add",
  "lemma": "add",
  "offset": 0
}
{
  "label": "NUMBER",
  "tag": "NUM",
  "value": "2",
  "lemma": "2",
  "offset": 4
}
{
  "label": "NUM",
  "tag": "NUM",
  "value": "1",
  "lemma": "1",
  "offset": 6
}
{
  "label": "NN",
  "tag": "NOUN",
  "value": "gig",
  "lemma": "gig",
  "offset": 8
}
{
  "label": "DOBJ",
  "tag": "NOUN",
  "value": "datafiles",
  "lemma": "datafile",
  "offset": 12
}
{
  "label": "PREP",
  "tag": "ADP",
  "value": "to",
  "lemma": "to",
  "offset": 22
}
{
  "label": "DET",
  "tag": "DET",
  "value": "the",
  "lemma": "the",
  "offset": 25
}
{
  "label": "NN",
  "tag": "NOUN",
  "value": "data",
  "lemma": "data",
  "offset": 29
}
{
  "label": "POBJ",
  "tag": "NOUN",
  "value": "tablespace",
  "lemma": "tablespace",
  "offset": 34
}

```

Now let's get csv output, as that is simple to parse in a Bash PoC script.

```text
$  jq --sort-keys -r ' .tokens | .[] | [.dependencyEdge["label"], .partOfSpeech["tag"], .text["content"], .lemma, .text["beginOffset"] ] | @csv '  t1.json   | sort -n -t, -k 5
"ROOT","VERB","add","add",0
"NUMBER","NUM","2","2",4
"NUM","NUM","1","1",6
"NN","NOUN","gig","gig",8
"DOBJ","NOUN","datafiles","datafile",12
"PREP","ADP","to","to",22
"DET","DET","the","the",25
"NN","NOUN","data","data",29
"POBJ","NOUN","tablespace","tablespace",34
```

Here the output has been sorted by the offset of each part of the sentence. 

We can reconstruct the sentence like this:

send the output to a file

```text
$  jq --sort-keys -r ' .tokens | .[] | [.dependencyEdge["label"], .partOfSpeech["tag"], .text["content"], .lemma, .text["beginOffset"] ] | @csv '  t1.json   | sort -n -t, -k 5 > t1.csv
```

```
$  cut -f3 -d, t1.csv
 "add"
 "2"
 "1"
 "gig"
 "datafiles"
 "to"
 "the"
 "data"
 "tablespace"
```


Now that we can parse and reconstruct the sentence, let's try to turn the sentence into an actionable command.

The script used to do this is just for demonstration purposes, and is somewhat crude, and not robust.

The data is read from the t1.csv file.


```text
>  ./txt2cmd.sh
0: ROOT,VERB,add,add,0
1: NUMBER,NUM,2,2,4
2: NUM,NUM,1,1,6
3: NN,NOUN,gig,gig,8
4: DOBJ,NOUN,datafiles,datafile,12
5: PREP,ADP,to,to,22
6: DET,DET,the,the,25
7: NN,NOUN,data,data,29
8: POBJ,NOUN,tablespace,tablespace,34
written command: 'add 2 1 gig datafiles to the data tablespace'
cmd: alter tablespace data add datafile size 1 gig

```

## All in one cmd

Call like this to run the default statement

```text
$  ./txt2cmd.sh
nlaJSONFile: /tmp/tmp.6FBxmP1NRW.json
csvRequestFile: /tmp/tmp.Y20XTscCII.csv
VERBOSE: 0
showCallStack: 0

working on this English statement: "add 2 1 gig datafiles to the data tablespace"

"ROOT - VERB - add - add - 0"
"NUMBER - NUM - 2 - 2 - 4"
"NUM - NUM - 1 - 1 - 6"
"NN - NOUN - gig - gig - 8"
"DOBJ - NOUN - datafiles - datafile - 12"
"PREP - ADP - to - to - 22"
"DET - DET - the - the - 25"
"NN - NOUN - data - data - 29"
"POBJ - NOUN - tablespace - tablespace - 34"
cmd: alter tablespace add datafile size 1 gig
```

However, it will not work properly with the following: 

```text
$  ./txt2cmd.sh  add a datafile to the data tablespace
nlaJSONFile: /tmp/tmp.KyGuwCebx5.json
csvRequestFile: /tmp/tmp.yGJ0cppEdR.csv
VERBOSE: 0
showCallStack: 0

working on this English statement: "add a datafile to the data tablespace"

"ROOT - VERB - add - add - 0"
"DET - DET - a - a - 4"
"DOBJ - NOUN - datafile - datafile - 6"
"PREP - ADP - to - to - 15"
"DET - DET - the - the - 18"
"NN - NOUN - data - data - 22"
"POBJ - NOUN - tablespace - tablespace - 27"
cmd: alter tablespace add datafile
```


```text
$ ./txt2cmd.sh  increase the data tablespace  by 20G
nlaJSONFile: /tmp/tmp.h8mnkPM7ht.json
csvRequestFile: /tmp/tmp.rxjltsaJ0U.csv
VERBOSE: 0
showCallStack: 0

working on this English statement: "increase the data tablespace by 20G"

"ROOT - VERB - increase - increase - 0"
"DET - DET - the - the - 9"
"NN - NOUN - data - data - 13"
"DOBJ - NOUN - tablespace - tablespace - 18"
"PREP - ADP - by - by - 29"
"POBJ - NOUN - 20G - 20G - 32"

UNKNOWN in buildTbsCmd

cmd: alter tablespace  increase
objAction: increase
```


