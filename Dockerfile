FROM alpine:3.9

LABEL "com.github.actions.name"="Merge back"
LABEL "com.github.actions.description"="Merge back master to develop"
LABEL "com.github.actions.icon"="chevrons-down"
LABEL "com.github.actions.color"="purple"

LABEL "repository"="http://github.com/razor54/gh-action-mergeback"
LABEL "homepage"="http://github.com/actions"
LABEL "maintainer"="Endre Czirbesz <endre@czirbesz.hu>"

RUN apk add --update --no-cache curl bash jq gettext

ADD entrypoint.sh /entrypoint.sh
ADD default_description.md /default_description.md
ENTRYPOINT ["/entrypoint.sh"]
