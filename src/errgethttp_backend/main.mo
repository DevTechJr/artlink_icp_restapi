

import Int "mo:base/Int";
import Time "mo:base/Time";
import Array "mo:base/Array";
import Text "mo:base/Text";
import Char "mo:base/Char";
import Blob "mo:base/Blob";
import Option "mo:base/Option";
import Iter "mo:base/Iter";
import HashMap "mo:base/HashMap";
import Buffer "mo:base/Buffer";

actor TransactionManager {
    // Define types
    type Transaction = {
        owner1: Text;
        owner2: Text;
        itemName: Text;
        verificationId: Text;
    };

    public type HttpRequest = {
        body: Blob;
        headers: [HeaderField];
        method: Text;
        url: Text;
    };

    public type HttpResponse = {
        body: Blob;
        headers: [HeaderField];
        status_code: Nat16;
    };

    public type HeaderField = (Text, Text);

    // Stable variable for persistence across upgrades
    stable var transactionsEntries: [(Text, Transaction)] = [];
    
    // In-memory HashMap for efficient lookups
    private var transactionsMap = HashMap.HashMap<Text, Transaction>(
        10,
        Text.equal,
        Text.hash
    );

    // Initialize the HashMap during deployment and upgrades
    system func preupgrade() {
        transactionsEntries := Iter.toArray(transactionsMap.entries());
    };

    system func postupgrade() {
        transactionsMap := HashMap.fromIter<Text, Transaction>(
            transactionsEntries.vals(),
            10,
            Text.equal,
            Text.hash
        );
    };

    // Helper functions remain the same
    private func removeQuery(str: Text): Text {
        let parts = Iter.toArray(Text.split(str, #char '?'));
        if (parts.size() > 0) {
            return parts[0];
        };
        return str;
    };

    private func getQueryParams(url: Text): HashMap.HashMap<Text, Text> {
        let queryParams = HashMap.HashMap<Text, Text>(
            10,
            Text.equal,
            Text.hash
        );
        
        let parts = Iter.toArray(Text.split(url, #char '?'));
        if (parts.size() > 1) {
            let queryString = parts[1];
            let pairs = Text.split(queryString, #char '&');
            for (pair in pairs) {
                let keyValue = Iter.toArray(Text.split(pair, #char '='));
                if (keyValue.size() == 2) {
                    let key = Text.trim(keyValue[0], #char ' ');
                    let value = Text.trim(keyValue[1], #char ' ');
                    queryParams.put(key, value);
                };
            };
        };
        
        return queryParams;
    };

    private func shiftCharacters(input: Text, shift: Nat32): Text {
        let charCode = func(c: Char): Char {
            let charCode = Char.toNat32(c);
            if (charCode >= 65 and charCode <= 90) {
                return Char.fromNat32(((charCode - 65 + shift) % 26) + 65);
            } else if (charCode >= 97 and charCode <= 122) {
                return Char.fromNat32(((charCode - 97 + shift) % 26) + 97);
            } else {
                return c;
            };
        };
        return Text.map(input, charCode);
    };

    // Updated debug output function to use HashMap
    private func getStoredTransactionsDebug(): Text {
        var debugOutput = "\n\nStored Transactions (" # Int.toText(transactionsMap.size()) # " total):\n";
        for ((hash, tx) in transactionsMap.entries()) {
            debugOutput #= "\nTransaction Hash: " # hash # ":\n";
            debugOutput #= "Sender: " # tx.owner1 # "\n";
            debugOutput #= "Receiver: " # tx.owner2 # "\n";
            debugOutput #= "Art Name: " # tx.itemName # "\n";
            debugOutput #= "-------------------";
        };
        return debugOutput;
    };

    // Helper function to format transactions as JSON
    private func formatTransactionsAsJSON(): Text {
        var jsonOutput = "{\n  \"transactions\": [";
        var isFirst = true;
        
        for ((hash, tx) in transactionsMap.entries()) {
            if (not isFirst) { jsonOutput #= ","; };
            jsonOutput #= "\n    {\n";
            jsonOutput #= "      \"hash\": \"" # hash # "\",\n";
            jsonOutput #= "      \"sender\": \"" # tx.owner1 # "\",\n";
            jsonOutput #= "      \"receiver\": \"" # tx.owner2 # "\",\n";
            jsonOutput #= "      \"artName\": \"" # tx.itemName # "\"\n";
            jsonOutput #= "    }";
            isFirst := false;
        };
        
        jsonOutput #= "\n  ]\n}";
        return jsonOutput;
    };

    // Candid UI functions
    public func generateHash(sender: Text, receiver: Text, artName: Text): async Text {
        let timestamp = Int.toText(Time.now());
        let input = sender # receiver # artName # timestamp;
        let verificationId = shiftCharacters(input, 3);

        let transaction: Transaction = {
            owner1 = sender;
            owner2 = receiver;
            itemName = artName;
            verificationId = verificationId;
        };
        
        transactionsMap.put(verificationId, transaction);
        return verificationId;
    };

    public query func verifyHash(hash: Text): async ?Transaction {
        return transactionsMap.get(hash);
    };

    public query func getAllTransactions(): async [(Text, Transaction)] {
        return Iter.toArray(transactionsMap.entries());
    };

    // Modified HTTP handler with new /allTransactions endpoint
    public query func http_request(req: HttpRequest): async HttpResponse {
        let path = removeQuery(req.url);
        let queryParams = getQueryParams(req.url);

        if (path == "/generate") {
            switch (queryParams.get("sender"), queryParams.get("receiver"), queryParams.get("artName")) {
                case (?sender, ?receiver, ?artName) {
                    let timestamp = Int.toText(Time.now());
                    let input = sender # receiver # artName # timestamp;
                    let verificationId = shiftCharacters(input, 3);

                    let transaction: Transaction = {
                        owner1 = sender;
                        owner2 = receiver;
                        itemName = artName;
                        verificationId = verificationId;
                    };
                    transactionsMap.put(verificationId, transaction);

                    return {
                        body = Text.encodeUtf8(
                            "Generated Hash: " # verificationId # 
                            "\n\nDebug Info:" #
                            "\nSender: " # sender #
                            "\nReceiver: " # receiver #
                            "\nArt Name: " # artName #
                            "\nTimestamp: " # timestamp #
                            getStoredTransactionsDebug()
                        );
                        headers = [("Content-Type", "text/plain")];
                        status_code = 200;
                    };
                };
                case _ {
                    return {
                        body = Text.encodeUtf8("Error: Missing required parameters (sender, receiver, artName)");
                        headers = [("Content-Type", "text/plain")];
                        status_code = 400;
                    };
                };
            };
        } else if (path == "/verify") {
            switch (queryParams.get("hash")) {
                case (?hash) {
                    switch (transactionsMap.get(hash)) {
                        case (?tx) {
                            return {
                                body = Text.encodeUtf8(
                                    "Valid hash! This transaction is verified."
                                );
                                headers = [("Content-Type", "text/plain")];
                                status_code = 200;
                            };
                        };
                        case null {
                            return {
                                body = Text.encodeUtf8(
                                    "Invalid hash: Transaction not found" #
                                    getStoredTransactionsDebug()
                                );
                                headers = [("Content-Type", "text/plain")];
                                status_code = 404;
                            };
                        };
                    };
                };
                case null {
                    return {
                        body = Text.encodeUtf8("Error: Missing hash parameter");
                        headers = [("Content-Type", "text/plain")];
                        status_code = 400;
                    };
                };
            };
        } else if (path == "/allTransactions") {
            return {
                body = Text.encodeUtf8(formatTransactionsAsJSON());
                headers = [
                    ("Content-Type", "application/json"),
                    ("Access-Control-Allow-Origin", "*")
                ];
                status_code = 200;
            };
        };

        return {
            body = Text.encodeUtf8("404 Not Found: " # path);
            headers = [("Content-Type", "text/plain")];
            status_code = 404;
        };
    };
}