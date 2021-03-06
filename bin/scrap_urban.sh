#!/bin/bash

# TODO:
# - grab missing VO from descriptions ex: https://www.urban-comics.com/superman-univers-3/
# - cleanup contenu VO
# - clean auteurs
# - add description?
# - find missing (urban link?)
# - generate hash for future indexation

requiredpages=$1
requiredcount=$2

editeur=urban

cachedir=".cache/$editeur"
datadir="data/$editeur"
catalog="catalogs/$editeur.csv"

cd $(dirname $0)/..
mkdir -p $cachedir $datadir catalogs

if ! [ -z "$requiredcount" ]; then
  count=$requiredcount
else
  count=100
fi

searchurl="https://www.urban-comics.com/wp-admin/admin-ajax.php"
query="action=mdf_get_ajax_auto_recount_data&mdf_ajax_content_redraw=true&shortcode_txt=mdf_custom+post_type%3Dproduct+template%3Dwoocommerce%2Fshop+per_page%3D${count}&content_redraw_page="

if ! [ -z "$requiredpages" ]; then
  pages=$requiredpages
else
  echo "- Querying total number of books..."
  pages=$(curl -sL "$searchurl" --data-raw "${query}1" |
           grep "class='page'"                         |
           tail -1                                     |
           sed -r 's/^.*>([0-9]+)<.*$/\1/')
  echo "  -> $((pages * count))"
fi

function escapeit { 
  perl -e 'use URI::Escape; print uri_escape shift();print"\n"' "$1" | sed 's/\s/_/g'
}

function cachedcurl {
  cache="$cachedir/"$(escapeit $1)
  if ! test -s $cache; then
    curl -sL "$1" > $cache
  fi
  cat $cache
}

function querymetas {
  cat $1                   |
   grep -iP "^($2)[^:]*:"  |
   sed -r 's/^[^:]*:\s*//' |
   sed 's/"/""/g'          |
   sed 's/^\s*/"/'         |
   sed 's/\s*$/"/'
}

function lowerize {
 cat                                                            |
 sed -r "s/([A-Z])([A-Z]+($|'S|[ ).,;\":?\!\/\#\-]))/\1\L\2/g"  |
 sed -r 's/(^|[" ])(Dc|Dvd|Brd|Tv|I[iv]+)([" .,;]|$)/\1\U\2\3/' |
 sed 's/Amere/Amère/'                                           |
 sed 's/ Of / of /'
}

echo "collection,série,titre,date,pages,prix,âge,scenario,dessin,contenu VO,EAN,url,url cover" > $datadir/catalog.csv
seq $pages | while read i; do
  echo "- Processing $count-books page $i/$pages..." 

  cache=$cachedir/catalog-by${count}-p${i}.html
  if ! test -s $cache || [ -z "$requiredpages" ]; then
    curl -sL $searchurl --data-raw "${query}${i}"  |
     jq .content                                   |
     sed -r 's/(\\n)+/\n/g'                        |
     sed -r 's/(\\t|\s)+/ /g'                      |
     sed -r 's/\\"/"/g' > $cache.tmp
    mv $cache{.tmp,}
  fi

  grep "EN SAVOIR PLUS" $cache          |
   sed -r 's/^.*href="([^"]*)".*$/\1/'  |
   while read bookurl; do
    echo "  -> $bookurl"

    output="$datadir/"$(escapeit $bookurl)
    cachedcurl "$bookurl"                                                                                           |
     python3 -c 'import html, sys; [print(html.unescape(l), end="") for l in sys.stdin]'                            |
     tr "\n" " "                                                                                                    |
     sed -r 's/\r//g'                                                                                               |
     sed -r "s/’/'/g"                                                                                               |
     sed -r 's/(<h[15]|<li[^>]*><b|<div class="[^"]*_album"|<img)/\n\1/g'                                           |
     sed -r 's#</(h[15]|li|div)>#</\1>\n#g'                                                                         |
     grep -P '(<h1|<h5 class="authors"|<li[^>]*><b|<div class="[^"]*_album"|<img class="[^"]*single-product-cover)' |
     sed -r 's/(<h1[^>]*>)/Titre : \1/'                                                                             |
     sed -r 's/^.*<img[^>]*src="([^"]*)"[^>]*>.*$/Cover : \1/'                                                      |
     sed -r 's/<[^>]+>//g'                                                                                          |
     sed -r 's/\s+/ /g'                                                                                             |
     sed -r 's/^\s//g'                                                                                              |
     sed -r 's/\s$//g' > $output

    cov=$(querymetas $output "Cover")

    age=$(querymetas $output "[AÂ]ge")

    tit=$(querymetas $output "Titre"        | lowerize)

    scn=$(querymetas $output "sc[eé]nariste"|
     sed 's/[ \-]*dessinateur[s :]*.*"$/"/' |
     sed 's/\s*,\s*/|/g'                    | lowerize)

    des=$(querymetas $output "sc[eé]nariste|dessinateur" |
     sed 's/^".*dessinateur[s :]*/"/'       |
     sed 's/, jr\./ Jr/g'                   |
     sed 's/\s*,\s*/|/g'                    | lowerize)

    col=$(querymetas $output "Collection"   | lowerize)

    ser=$(querymetas $output "S[eé]rie"     | lowerize)

    vos=$(querymetas $output "Contenu"      |
     sed -r 's/^\(?Cont(enu|ient)[ :]*//'   | lowerize)

    dat=$(querymetas $output "Date" |
     sed 's/janvier/01/'            |
     sed 's/février/02/'            |
     sed 's/mars/03/'               |
     sed 's/avril/04/'              |
     sed 's/mai/05/'                |
     sed 's/juin/06/'               |
     sed 's/juillet/07/'            |
     sed 's/août/08/'               |
     sed 's/septembre/09/'          |
     sed 's/octobre/10/'            |
     sed 's/novembre/11/'           |
     sed 's/décembre/12/'           |
     sed -r 's/([0-9]+) ([0-9]+) ([0-9]+)/\3-\2-\1/')

    pag=$(querymetas $output "Pag"  |
     sed 's/"0 page"/""/'           |
     sed 's/ pages//')

    pri=$(querymetas $output "Prix" |
     sed 's/ €//'                   |
     sed -r 's/(\..)"/\10"/'        |
     sed -r 's/("[0-9]+)"/\1.00"/')

    ean=$(querymetas $output "EAN")

    if ! [ -z "$pri" ]; then
      echo "$col,$ser,$tit,$dat,$pag,$pri,$age,$scn,$des,$vos,$ean,$bookurl,$cov" >> $datadir/catalog.csv
    fi
   done
 done

xsv sort -s collection,série,date,titre $datadir/catalog.csv > $catalog

