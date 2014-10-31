for b in $(git for-each-ref --sort=-committerdate refs/remotes --format='%(refname:short)'); do
    echo $b
    git checkout $b
    if [ -f ./script.sh ]; then
        ./script.sh install
    fi
done
#git checkout master