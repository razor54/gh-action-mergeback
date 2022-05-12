#!/bin/bash
set -eu

TRUNK=${TRUNK_BRANCH:=master}

# env | grep GITHUB

case $GITHUB_REF in
  */"$TRUNK") echo "We are on $TRUNK, let's merge.";;
         *) echo "Not on $TRUNK (${GITHUB_REF}), do nothing."; exit 0;;
esac 

# First of all create a temporary branch
# Useful for handling merge conflicts with protected branches
echo "Creating a temporary branch..."
tmp=$(mktemp)
TMP_BRANCH=mergeback-to-${BASE_BRANCH:=develop}
SHA=$(curl --silent -H "Authorization: token ${GITHUB_TOKEN}" https://api.github.com/repos/${GITHUB_REPOSITORY}/git/refs/heads/${TRUNK} | jq -r '.object.sha')
tmp=$(mktemp)
payload=$(cat <<EOF 
{
  "ref": "refs/heads/${TMP_BRANCH}",
  "sha": "${SHA}"
}
EOF
)
status_code=$(curl --silent --output ${tmp}  \
    --write-out "%{http_code}" \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Content-type: application/json" \
    -X POST https://api.github.com/repos/${GITHUB_REPOSITORY}/git/refs \
    -d "${payload}")
output=$(cat ${tmp})
rm ${tmp}
# Valid status codes
# 201	Created
# 422	Validation failed

# Test if branch already existed, if so update it
if test ${status_code} -eq 422; then #Existing branch
    echo "Branch already exists, let's update it..."
    tmp=$(mktemp)
    payload=$(cat <<EOF 
{
  "sha":"${SHA}",
  "force":true
}
EOF
)

    status_code=$(curl --silent --output ${tmp} \
        --write-out "%{http_code}" \
        -H "Authorization: token ${GITHUB_TOKEN}" \
        -H "Content-type: applicaton/json" \
        -X PATCH \
        https://api.github.com/repos/${GITHUB_REPOSITORY}/git/refs/heads/${TMP_BRANCH} \
        -d "${payload}")
    output=$(cat ${tmp})
    rm ${tmp}
    if test ${status_code} -ne 200; then
        echo "An error occured trying to update the temporary branch, status code ${status_code}"
        echo $output | jq
        exit 1
    fi
fi

# Let's create a PR

echo "Creating a PR..."
payload=$(cat <<EOF 
{
  "base": "${BASE_BRANCH}",
  "head": "${TMP_BRANCH}",
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
        -X GET "https://api.github.com/repos/${GITHUB_REPOSITORY}/pulls?head=${TMP_BRANCH}&base=${BASE_BRANCH}" )
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

    team_reviewers=(${TEAM_REVIEWERS:-})
    reviewers=(${REVIEWERS:-})
    if [ ${#team_reviewers[@]} -neq 0 -a ${#team_reviewers[@]} -neq 0 ]; then
        payload=$(cat << EOF 
{
    "reviewers": $(jq -n --arg inarr "${reviewers}" '$inarr | split(",")' --compact-output),
    "team_reviewers": $(jq -n --arg inarr "${team_reviewers}" '$inarr | split(",")' --compact-output)
}
EOF
    else
)
      echo "Requesting review from ${GITHUB_ACTOR}"
      payload=$(cat <<EOF 
{
  "reviewers": [
    "${GITHUB_ACTOR}"
  ]
}
EOF
)
    fi
    curl --silent --output /dev/null --fail \
      -H "Authorization: token ${GITHUB_TOKEN}" \
      -H "Content-type: application/json" \
      -X POST https://api.github.com/repos/${GITHUB_REPOSITORY}/pulls/${pr_no}/requested_reviewers \
      -d "${payload}"
fi
