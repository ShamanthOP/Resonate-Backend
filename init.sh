#!/usr/bin/env bash

OS="$(uname -s)"

case "$OS" in
    Linux*)     OS_TYPE=Linux;;
    Darwin*)    OS_TYPE=Mac;;
    *)          OS_TYPE="UNKNOWN:$OS"
esac


echo "Operating System: $OS_TYPE"

echo "Installing Dependencies...."

if [ "$OS_TYPE" = "Mac" ]; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    brew install appwrite
    brew install livekit
    brew install --cask devtunnel
    brew install livekit-cli
else
    curl -sL https://appwrite.io/cli/install.sh | bash
    curl -sSL https://get.livekit.io | bash
    curl -sL https://aka.ms/DevTunnelCliInstall | bash
    curl -sSL https://get.livekit.io/cli | bash
fi


while true; do
    devtunnel login
    if [ $? -eq 0 ]; then
        break
    else
        echo "devtunnel login failed. Please try again."
    fi
done


check_status() {
    if [ $? -ne 0 ]; then
        echo "Error: $1 failed to start. Exiting script."
        exit 1
    fi
}

# Start the first devtunnel on port 80
echo "Starting devtunnel on port 80..."
devtunnel host -p 80 --allow-anonymous --protocol http --host-header unchanged > /dev/null 2>&1 &
check_status "devtunnel on port 80"

# Start the second devtunnel on port 7880
echo "Starting devtunnel on port 7880..."
devtunnel host -p 7880 --allow-anonymous --protocol http --host-header unchanged > /dev/null 2>&1 &
check_status "devtunnel on port 7880"

sleep 2

echo "Both devtunnels started successfully."

# Get the list of active tunnels and extract the URLs
echo "Fetching the list of active tunnels"
tunnel_list=$(devtunnel list)

echo $tunnel_list
tunnel_ids=$(echo "$tunnel_list" | grep -o '\b[a-z0-9-]*\.inc1\b')

# Split the IDs into individual variables if needed
tunnel_id_1=$(echo "$tunnel_ids" | sed -n '1p')
tunnel_id_2=$(echo "$tunnel_ids" | sed -n '2p')

# Output the extracted tunnel IDs
echo "Tunnel ID for Appwrite: $tunnel_id_1"
echo "Tunnel ID for Livekit: $tunnel_id_2"


docker run -it --add-host host.docker.internal:host-gateway --rm \
    --volume /var/run/docker.sock:/var/run/docker.sock \
    --volume "$(pwd)"/appwrite:/usr/src/code/appwrite:rw \
    --entrypoint="install" \
    appwrite/appwrite:latest


projectId="resonate"


# Remove previous Appwrite Cli data
rm -rf ~/.appwrite | bash

# Ask contributor account credentials   
while true; do
    appwrite login --endpoint "http://localhost:80/v1"
    if [ $? -eq 0 ]; then
        break
    else
        echo "Appwrite Login failed. Please try again."
    fi
done


echo "Starting resonate project set up...."
# Get team id for project creation
read -p "Please provide the team Id as instructed in the Resonate Set Up Guide:" teamId

# Creating the project
appwrite projects create --project-id resonate --name Resonate --team-id "$teamId"


# Creating IOS and Andriod platforms
appwrite projects create-platform --project-id "$projectId" --type flutter-android --key com.resonate.resonate --name Resonate
appwrite projects create-platform --project-id "$projectId" --type flutter-ios --key com.resonate.resonate --name Resonate

# Creating Server Key and Retreiving it from response
create_key_response=$(appwrite projects create-key --project-id "$projectId" --name "Appwrite Server Key" --scopes 'sessions.write' 'users.read' 'users.write' 'teams.read' 'teams.write' 'databases.read' 'databases.write' 'collections.read' 'collections.write' 'attributes.read' 'attributes.write' 'indexes.read' 'indexes.write' 'documents.read' 'documents.write' 'files.read' 'files.write' 'buckets.read' 'buckets.write' 'functions.read' 'functions.write' 'execution.read' 'execution.write' 'locale.read' 'avatars.read' 'health.read' 'providers.read' 'providers.write' 'messages.read' 'messages.write' 'topics.read' 'topics.write' 'subscribers.read' 'subscribers.write' 'targets.read' 'targets.write' 'rules.read' 'rules.write' 'migrations.read' 'migrations.write' 'vcs.read' 'vcs.write' 'assistant.read')
secret=$(echo "$create_key_response" | awk -F' : ' '/secret/ {print $2}')
echo $create_key_response
echo $secret


# Pushing Server Key as env variable for cloud functions to use
appwrite project create-variable --key APPWRITE_API_KEY --value "$secret"


# Push endpoint as environment variable for functions to use (host.docker.internal used to access localhost from inside of script)
appwrite project create-variable --key APPWRITE_ENDPOINT --value "http://host.docker.internal:80/v1"



# Ask contributor for Oauth2 provider config (Google. Github)
echo "Please follow the Set Up Guide on Resonate to create the Oauth2 credentials for Google and Github"

echo "ngrok tunnel Domain Name: $ngrok_url"
read -p "Enter the Google App ID: " googleAppId
read -p "Enter the Google App Secret: " googleSecret
appwrite projects update-o-auth-2 --project-id "$projectId" --provider 'google' --appId "$googleAppId" --secret "$googleSecret" --enabled true

read -p "Enter the GitHub App ID: " githubAppId
read -p "Enter the GitHub App Secret: " githubSecret
appwrite projects update-o-auth-2 --project-id "$projectId" --provider 'github' --appId "$githubAppId" --secret "$githubSecret" --enabled true

# Pushing the project's core defined in appwrite.json
appwrite push collection
appwrite push function
appwrite push bucket

echo "---- Appwrite Set Up complete ----"
echo "Setting Up Livekit now ..."
# Push Livekit credentials as env variables for functions to use
while true; do
    read -p "Do you wish to opt for Livekit Cloud or Host Livekit locally? For Locally: y, For Cloud: n (y/n)" isLocalDeployment
    if [[ $isLocalDeployment == "y" || $isLocalDeployment == "Y" ]]; then

        echo "You chose to host Livekit locally."

        # check if Livekit server already running
        PROCESS_ID=$(pgrep -f "livekit-server")
        if [ ! -z "$PROCESS_ID" ]; then
            kill $PROCESS_ID
            echo "Livekit Server Already Runing Terminating and Starting Again..."
        else
            echo "Starting Livekit Server"
        fi

        # Command to Start Livekit Server
        livekit-server --dev --bind 0.0.0.0 > livekit.log 2>&1 &

        livekitHostURL="http://host.docker.internal:7880"
        livekitSocketURL="wss://host.docker.internal:7880"
        livekitAPIKey="devkey"
        livekitAPISecret="secret"
        break

    elif [[ $isLocalDeployment == "n" || $isLocalDeployment == "N" ]]; then
        echo "You chose to use Livekit Cloud."
        echo "Please follow the steps on the Guide to Set Up Livekit Cloud, hence getting your self Livekit host url, socket url, API key, API secret"
        read -p "Please Provide Livekit Host Url: " livekitHostURL
        read -p "Please Provide Livekit Socket Url: " livekitSocketURL
        read -p "Please Provide Livekit API key: " livekitAPIKey
        read -p "Please Provide Livekit API secret: " livekitAPISecret
        break

    else
        echo "Invalid input. Please enter 'y' for local or 'n' for cloud."
    fi
done


# Push Livekit credentials as env variables for functions to use
echo "Pushing Livekit credentials as env variables if you need any changes do them in your Appwrtie Resoante projects Global Env variables"
appwrite project create-variable --key LIVEKIT_HOST --value "$livekitHostURL"
appwrite project create-variable --key LIVEKIT_SOCKET_URL --value "$livekitSocketURL"
appwrite project create-variable --key LIVEKIT_API_KEY --value "$livekitAPIKey"
dcreate-variable --key LIVEKIT_API_SECRET --value "$livekitAPISecret"

echo "Tunnel ID for Appwrite: $tunnel_id_1"
echo "Tunnel ID for Livekit: $tunnel_id_2"