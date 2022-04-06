#!/bin/bash

cd $(dirname $0)/..
mkdir -p cache/urban data/urban catalogs

if ! [ -z "$2" ]; then
  count=$2
else
  count=100
fi

searchurl="https://www.urban-comics.com/wp-admin/admin-ajax.php"
query="action=mdf_get_ajax_auto_recount_data&mdf_ajax_content_redraw=true&shortcode_txt=mdf_custom+post_type%3Dproduct+template%3Dwoocommerce%2Fshop+per_page%3D${count}&content_redraw_page="

if ! [ -z "$1" ]; then
  pages=$1
else
  echo "- Querying total number of books..."
  pages=$(curl -sL "$searchurl" --data-raw "${query}1" |
           grep "class='page'"                 |
           tail -1                             |
           sed -r 's/^.*>([0-9]+)<.*$/\1/')
  echo "  -> $((pages * count))"
fi

function escapeit { 
  perl -e 'use URI::Escape; print uri_escape shift();print"\n"' "$1" | sed 's/\s/_/g'
}

function cachedcurl {
  cache="cache/urban/"$(escapeit $1)
  if ! test -s $cache; then
    curl -sL "$1" > $cache
  fi
  cat $cache
}

function querymetas {
  cat $1 | grep -i "^$2" | awk -F "|" '{print $2}' | sed 's/"/""/g' | sed 's/^\s*/"/' | sed 's/\s*$/"/'
}

rm -f data/urban/catalog.csv
seq $pages |
 while read i; do
  echo "- Querying $count-books page $i/$pages..." 
  curl -sL $searchurl --data-raw "${query}${i}"  |
   jq .content                                   |
   sed -r 's/(\\n)+/\n/g'                        |
   sed -r 's/(\\t|\s)+/ /g'                      |
   sed -r 's/\\"/"/g' > cache/urban/catalog-p${i}.html
  grep "EN SAVOIR PLUS" cache/urban/catalog-p${i}.html |
   sed -r 's/^.*href="([^"]*)".*$/\1/'           |
   while read bookurl; do
    echo "  -> $bookurl"
    output="data/"$(escapeit $bookurl)
    cachedcurl "$bookurl"                                                                |
     python3 -c 'import html, sys; [print(html.unescape(l), end="") for l in sys.stdin]' |
     tr "\n" " "                                                                         |
     sed -r 's/(<h1|<li[^>]*><b|<div class="[^"]*_album")/\n\1/g'                        |
     sed -r 's#</(h1|li|div)>#</\1>\n#g'                                                 |
     grep -P '(<h1|<li[^>]*><b|<div class="[^"]*_album")'                                |
     sed -r 's/<[^>]+>//g'                                                               |
     sed -r 's/^\s+//g'                                                                  |
     sed -r 's/\s*:\s*/|/' > $output
    #cat $output
    title='"'$(cat $output | head -1 | sed 's/"/""/g')'"'
    age=$(querymetas $output "[AÂ]ge")
    col=$(querymetas $output "Collection")
    ser=$(querymetas $output "S[eé]rie")
    dat=$(querymetas $output "Date")
    pag=$(querymetas $output "Pag")
    ean=$(querymetas $output "EAN")
    pri=$(querymetas $output "Prix")
    vos=$(querymetas $output "Contenu")
# TODO:
# - add auteurs
# - add description?
# - generate hash for future indexation
    if ! [ -z "$pri" ]; then
      echo "$title;$ser;$col;$age;$dat;$pag;$ean;$vos;$pri;$bookurl" >> data/urban/catalog.csv
    fi
   done
 done
echo "titre;série;collection;âge;date;pages;EAN;contenu VO;prix;url" > catalogs/urban.csv
sort -u data/urban/catalog.csv >> catalogs/urban.csv
