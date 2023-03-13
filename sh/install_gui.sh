#!/bin/bash
# Git test
# Shell script for installing Ergo Node on any platform.
# markglasgow@gmail.com 
# -------------------------------------------------------------------------
# Totally butchered by rustinmyeye

export BLAKE_HASH="324dcf027dd4a30a932c441f365a25e86b173defa4b8e58948253471b81b72cf"

# Set some environment variables
set_environment(){
    export API_KEY="dummy"
    
    let j=0
    #OS=$(uname -m)

    
    dt=$(date '+%d/%m/%Y %H:%M:%S');
    let i=0
    let PERCENT_BLOCKS=100
    let PERCENT_HEADERS=100

    # Check for python
    if ! hash python3; then
        echo ""
        #curl https://pyenv.run | bash
        #echo "Python installed, please re-run"
        #https://github.com/pyenv-win/pyenv-win
        exit 1
    fi
   

    # Check Java
    jver=`java -version 2>&1 | grep 'version' 2>&1 | awk -F\" '{ split($2,a,"."); print a[1]"."a[2]}'`
    if [[ $jver > "1.8" ]]; then                
        echo ""
        #exit 1
    else
        echo "Java="$jver
    fi
   

set_configuration (){
        echo "
                ergo {
                    node {
                        # Full options available at 
                        # https://github.com/ergoplatform/ergo/blob/master/src/main/resources/application.conf
                        
                        mining = false
                        # Skip validation of transactions in the mainnet before block 417,792 (in v1 blocks).
                        # Block 417,792 is checkpointed by the protocol (so its UTXO set as well).
                        # The node still applying transactions to UTXO set and so checks UTXO set digests for each block.
                        skipV1TransactionsValidation = true
                    }

                }      
                        
                scorex {
                    restApi {
                        # Hex-encoded Blake2b256 hash of an API key. 
                        # Should be 64-chars long Base16 string.
                        # below is the hash of the string 'hello'
                        # replace with your actual hash 
                        apiKeyHash = "$BLAKE_HASH"
                        
                    }
                
                }
        " > ergo.conf

}

start_node(){
    java -jar $JVM_HEAP_SIZE ergo.jar --mainnet -c ergo.conf > server.log 2>&1 & 
    echo "#### Waiting for a response from the server. ####"
    while ! curl --output /dev/null --silent --head --fail http://localhost:9053; do sleep 1 && error_log; done;  # wait for node be ready with progress bar
    
}

# Set basic config for boot, boot & get the hash and then re-set config 
first_run() {

            
        ### Download the latest .jar file                                                                    
        if [ ! -e *.jar ]; then 
            echo "- Retrieving latest node release.."
            LATEST_ERGO_RELEASE=$(curl -s "https://api.github.com/repos/ergoplatform/ergo/releases/latest" | awk -F '"' '/tag_name/{print $4}')
            LATEST_ERGO_RELEASE_NUMBERS=$(echo ${LATEST_ERGO_RELEASE} | cut -c 2-)
            ERGO_DOWNLOAD_URL=https://github.com/ergoplatform/ergo/releases/download/${LATEST_ERGO_RELEASE}/ergo-${LATEST_ERGO_RELEASE_NUMBERS}.jar
            echo "- Downloading Latest known Ergo release: ${LATEST_ERGO_RELEASE}."
            curl --silent -L ${ERGO_DOWNLOAD_URL} --output ergo.jar
        fi 

    
        
        # API 
        read -p "
    #### Please create a password. #### 

    This will be used to unlock your API. 

    Generally using the same API key through the entire sync process can prevent 'Bad API Key' errors:

    " input

        export API_KEY=$input
        echo "$API_KEY" > api.conf

        
        
        start_node
        
        export BLAKE_HASH=$(curl --silent -X POST "http://localhost:9053/utils/hash/blake2b" -H "accept: application/json" -H "Content-Type: application/json" -d "\"$input\"")
        echo "$BLAKE_HASH" > blake.conf
        #echo "BLAKE_HASH:$BLAKE_HASH"
        
        func_kill

        # Add blake hash
        set_configuration
        
        start_node
        
        # Add blake hash
        set_configuration

}

func_kill(){
    case "$(uname -s)" in

    CYGWIN*|MINGW32*|MSYS*|MINGW*)
        echo 'MS Windows'
        netstat -ano | findstr :9053
        taskkill /PID 9053 /F
        ;;

    armv7l*|aarch64)
        echo "on Pi!"
        #kill -9 $(lsof -t -i:9053)
        #kill -9 $(lsof -t -i:9030)
        killall -9 java
        sleep 10
        ;;
    *) #Other
        killall -9 java
        sleep 10
        ;;
    esac

}

error_log(){
    inputFile=ergo.log
    
    if egrep 'ERROR\|WARN' "$inputFile" ; then
        echo "WARN/ERROR:" $egrep
        echo "$egrep" >> error.log
    elif egrep 'Got GetReaders request in state (None,None,None,None)\|port' "$inputFile" ; then
        echo "Readers not ready. If this keeps happening we'll attempt to restart: $i"
        ((i=i+1)) 
    elif egrep 'Invalid z bytes' "$inputFile" ; then
        echo "zBYTES error:" $egrep
        echo "$egrep" >> error.log
    
    fi

    if [ $i -gt 10 ]; then
        i=0
        echo i: $i
        #func_kill
        curl -X POST --max-time 10 "http://127.0.0.1:9053/node/shutdown" -H "api_key: $API_KEY"
        start_node
        
    fi

}

check_status(){
    LRED="\033[1;31m" # Light Red
    LGREEN="\033[1;32m" # Light Green
    NC='\033[0m' # No Color

    string=$(curl -sf --max-time 20 "${1}")
    
    if [ -z "$string" ]; then
        echo -e "${LRED}${1} is down${NC}"
        func_kill
        
        start_node
        print_console
    else
       echo -e "${LGREEN}${1} is online${NC}"
    fi
}

get_heights(){

    check_status "localhost:9053/info"

        API_HEIGHT2==$(\
                curl --silent --max-time 10 --output -X GET "https://api.ergoplatform.com/api/v1/networkState" -H "accept: application/json" )

        HEADERS_HEIGHT=$(\
            curl --silent --max-time 10 --output -X GET "http://localhost:9053/info" -H "accept: application/json" \
            | python3 -c "import sys, json; print(json.load(sys.stdin)['headersHeight']);"\
        )

        HEIGHT=$(\
        curl --silent --max-time 10 --output -X GET "http://localhost:9053/info" -H "accept: application/json"   \
        | python3 -c "import sys, json; print(json.load(sys.stdin)['parameters']['height']);"\
        )
        
        FULL_HEIGHT=$(\
        curl --silent --max-time 10 --output -X GET "http://localhost:9053/info" -H "accept: application/json"   \
        | python3 -c "import sys, json; print(json.load(sys.stdin)['fullHeight']);"\
        )               
        

    
    API_HEIGHT=${API_HEIGHT2:92:6}
    # Calculate %
    if [ -n "$API_HEIGHT" ] && [ "$API_HEIGHT" -eq "$API_HEIGHT" ] 2>/dev/null; then
        
        
        if [ -n "$HEADERS_HEIGHT" ] && [ "$HEADERS_HEIGHT" -eq "$HEADERS_HEIGHT" ] 2>/dev/null; then
            let expr PERCENT_HEADERS=$(( ( ($API_HEIGHT - $HEADERS_HEIGHT) * 100) / $API_HEIGHT   )) 
        fi

        if [ -n "$HEIGHT" ] && [ "$HEIGHT" -eq "$HEIGHT" ] 2>/dev/null; then
            let expr PERCENT_BLOCKS=$(( ( ($API_HEIGHT - $HEIGHT) * 100) / $API_HEIGHT   ))
        fi        
        
        # if height==headersHeight then we are syncronised. 
        if [ -n "$HEADERS_HEIGHT" ] && [ "$HEADERS_HEIGHT" -eq "$HEIGHT" ] 2>/dev/null; then
            echo "HeadersHeight == Height"
            echo "Node is syncronised"
            exit 1

        fi

        # If HeadersHeight < Height then something has gone wrong
        if [ -n "$HEADERS_HEIGHT" ] && [ "$HEADERS_HEIGHT" -lt "$HEIGHT" ] 2>/dev/null; then
            echo "HeadersHeight < Height"
            echo "Mis-sync!"
            exit 1

        fi
   
        

    fi
    
} 
    
print_console() {
    while sleep 1
        do
        clear
        
        printf "%s    \n\n" \
        "To use the API, enter your password ('$API_KEY') on 127.0.0.1:9053/panel under 'Set API key'."\
        "Please follow the next steps on docs.ergoplatform.org to initialise your wallet."  \
        "For best results please disable any sleep mode while syncing"  \
        "Sync Progress;"\
        "### Headers: ~$(( 100 - $PERCENT_HEADERS ))% Complete ($HEADERS_HEIGHT/$API_HEIGHT) ### "\
        "### Blocks:  ~$(( 100 - $PERCENT_BLOCKS ))% Complete ($HEIGHT/$API_HEIGHT) ### "
        
        echo ""
        error_log
        dt=$(date '+%d/%m/%Y %H:%M:%S');
        echo "$dt: HEADERS: $HEADERS_HEIGHT, HEIGHT:$HEIGHT" >> height.log

        get_heights  
    done
}

# Check for the prescence of log files
count=`ls -1 blake.conf 2>/dev/null | wc -l`
if [ $count != 0 ]; then   
    API_KEY=$(cat "api.conf")
    echo "api.conf: API Key is set to: $API_KEY"
    BLAKE_HASH=$(cat "blake.conf")
    echo "blake.conf: Blake hash is: $BLAKE_HASH"
    echo "."
else 
    # If no .log file - we assume first run
    echo "."
   clear
fi

# Set some environment variables
set_environment     

## Minimal Config
echo "
    ergo {
        node {
            mining = false
        }

    }" > ergo.conf
        
## Node start command
echo "
#!/bin/sh  
while true
do
java -jar -Xmx1G ergo.jar --mainnet -c ergo.conf > server.log 2>&1 &
    sleep 100
done" > start.sh
    
chmod +x start.sh

## Download .jar
echo "- Retrieving latest node release.."
LATEST_ERGO_RELEASE=$(curl -s "https://api.github.com/repos/ergoplatform/ergo/releases/latest" | awk -F '"' '/tag_name/{print $4}')
LATEST_ERGO_RELEASE_NUMBERS=$(echo ${LATEST_ERGO_RELEASE} | cut -c 2-)
ERGO_DOWNLOAD_URL=https://github.com/ergoplatform/ergo/releases/download/${LATEST_ERGO_RELEASE}/ergo-${LATEST_ERGO_RELEASE_NUMBERS}.jar
echo "- Downloading Latest known Ergo release: ${LATEST_ERGO_RELEASE}."
curl --silent -L ${ERGO_DOWNLOAD_URL} --output ergo.jar

##Start node
echo "Starting the node..."

tmux new-session -d -s my_session 'sh start.sh && sleep 5'
# Launch in browser
#python3${ver:0:1} -mwebbrowser http://127.0.0.1:9053/panel 
#python3${ver:0:1} -mwebbrowser http://127.0.0.1:9053/info 

# Print to console
print_console   