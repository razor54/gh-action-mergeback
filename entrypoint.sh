#!/bin/bash
set -eu

TRUNK=${TRUNK_BRANCH:=master}

# env | grep GITHUB

case $GITHUB_REF in
  */"$TRUNK") echo "We are on $TRUNK, let's merge.";;
         *) echo "Not on $TRUNK (${GITHUB_REF}), do nothing."; exit 0;;
esac 

# Let's create a PR

echo "Creating a PR..."
payload=$(cat <<EOF 
{
  "base": "${BASE_BRANCH:=develop}",
  "head": "${TRUNK}",
  "title": "Merging back ${TRUNK}"
}
EOF
)
tmp=$(mktemp)
status_code=$(curl --silent --output ${tmp} \
    --write-out "%{http_code}" \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Content-type: application/json" \
    -X POST https://api.github.com/repos/${GITHUB_REPOSITORY}/pulls \
    -d "${payload}")
output=$(cat ${tmp})
rm ${tmp}

if test ${status_code} -eq 422; then #Existing PR
    echo "A PR already exists, let's find its number..."
    tmp=$(mktemp)
    status_code=$(curl --silent --output ${tmp} \
        --write-out "%{http_code}" \
        -H "Authorization: token ${GITHUB_TOKEN}" \
        -H "Content-type: application/json" \
        -X GET "https://api.github.com/repos/${GITHUB_REPOSITORY}/pulls?head=${TRUNK}&base=${BASE_BRANCH}" )
    output=$(cat ${tmp})
    rm ${tmp}
    if test ${status_code} -ne 200; then
        echo "An error occured trying to find the existing PR, status code ${status_code}"
        echo $output | jq
        exit 1
    fi
    pr_no=$(echo $output | jq -r '.[0].number')
    echo "Found an existing PR (#${pr_no}), let's try and use that..."
elif test ${status_code} -ne 201; then # Other failure
    echo "Creating a PR has failed with status code ${status_code}"
    echo $output | jq
    exit 1
else
    pr_no=$(echo $output | jq -r '.number')
fi

echo "Merging PR..."
tmp=$(mktemp)
status_code=$(curl --silent --output ${tmp} \
    --write-out "%{http_code}" \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Content-type: application/json" \
    -X PUT https://api.github.com/repos/${GITHUB_REPOSITORY}/pulls/${pr_no}/merge )
output=$(cat ${tmp})
rm ${tmp}

if test ${status_code} -ne 200; then
    echo "The merge has failed with status code ${status_code}"
    echo $output | jq
    
    if [ -e ${DESC_PATH:=".github/merge-instructions.md"} ] ; then
        merge_instructions=${DESC_PATH}
    else
        merge_instructions='/default_description.md'
    fi
    
    echo "Updating PR description..."
    payload=$(jq -n --rawfile a ${merge_instructions} '.body=$a' | envsubst)
    curl --silent --output /dev/null --fail \
      -H "Authorization: token ${GITHUB_TOKEN}" \
      -H "Content-type: application/json" \
      -X PATCH https://api.github.com/repos/${GITHUB_REPOSITORY}/pulls/${pr_no} \
      -d "${payload}"

    echo "Requesting review from ${GITHUB_ACTOR}"
    payload=$(cat <<EOF 
{
  "reviewers": [
    "${GITHUB_ACTOR}"
  ]
}
EOF
)
    curl --silent --output /dev/null --fail \
      -H "Authorization: token ${GITHUB_TOKEN}" \
      -H "Content-type: application/json" \
      -X POST https://api.github.com/repos/${GITHUB_REPOSITORY}/pulls/${pr_no}/requested_reviewers \
      -d "${payload}"
fi
