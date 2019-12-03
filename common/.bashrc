
# Prompt
export PS1="\[\e[0;96m\]\w \[\e[0;35m\]\$(git rev-parse --abbrev-ref HEAD 2> /dev/null) \[\e[0;37m\]\$\[\e[0m\] "
#export PS1='\h:\W \u\$ '
#export PS1=$'\\[\E]0;\\u: \\w\a\\]\\[\E[01;32m\\]\\u\\[\E[00m\\]:\\[\E[01;34m\\]\\w\\[\E[00m\\]$ '