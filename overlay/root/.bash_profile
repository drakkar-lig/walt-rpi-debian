# see https://superuser.com/questions/175799/does-bash-have-a-hook-that-is-run-before-executing-a-command
preexec_invoke_exec () {
    [ -n "$COMP_LINE" ] && return  # do nothing if completing
    [ "$BASH_COMMAND" = "$PROMPT_COMMAND" ] && return # don't cause a preexec for $PROMPT_COMMAND
    local this_command=$(HISTTIMEFORMAT= history 1 | sed -e "s/^[ ]*[0-9]*[ ]*//");
    echo "RUN $this_command" >> /etc/walt/Dockerfile
}

auto_build_dockerfile() {
    if [ ! -f /.dockerenv ]
    then    # not in a container
        return
    fi
    if [ ! -f /etc/walt/Dockerfile ]
    then
        mkdir -p /etc/walt
        cat > /etc/walt/Dockerfile << EOF
# Commands run in walt image shell are saved here.
# For easier image maintenance, you can retrieve
# and edit this file to use it as a Dockerfile.
EOF
    fi
    trap 'preexec_invoke_exec' DEBUG
}

auto_build_dockerfile

# Display the node hostname on client terminal
echo -en "\x1b]2;$(hostname)\x07"
