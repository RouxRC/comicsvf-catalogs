#!/bin/bash

cd $(dirname $0)/..
mkdir -p cache

searchurl="https://www.urban-comics.com/wp-admin/admin-ajax.php"
query="action=mdf_get_ajax_auto_recount_data&mdf_ajax_content_redraw=true&shortcode_txt=mdf_custom+post_type%3Dproduct+template%3Dwoocommerce%2Fshop+per_page%3D100&content_redraw_page="

echo "- Querying total number of books..."
pages=$(curl -sL "$searchurl" --data-raw "${query}1" |
         grep "class='page'"                 |
         tail -1                             |
         sed -r 's/^.*>([0-9]+)<.*$/\1/')
echo "  -> $((pages * 100))"

function escapeit { 
  perl -e 'use URI::Escape; print uri_escape shift();print"\n"' "$1" | sed 's/\s/_/g'
}

function cachedcurl {
  cache="cache/"$(escapeit $1)
  if ! test -s $cache; then
    curl -sL "$1" > $cache
  fi
  cat $cache
}

seq $pages | while read i; do
  echo "- Querying 100-books page $i/$pages..." 
  curl -sL $searchurl --data-raw "${query}${i}"  |
   jq .content                                   |
   sed -r 's/(\\n)+/\n/g'                        |
   sed -r 's/(\\t|\s)+/ /g'                      |
   sed -r 's/\\"/"/g' > cache/catalog-p${i}.html
  grep "EN SAVOIR PLUS" cache/catalog-p${i}.html |
   sed -r 's/^.*href="([^"]*)".*$/\1/'           |
   while read bookurl; do
     cachedcurl "$bookurl"                                                                |
      python3 -c 'import html, sys; [print(html.unescape(l), end="") for l in sys.stdin]' |
      grep -P '(<h1|<li[^>]*><b)'
   done
done
