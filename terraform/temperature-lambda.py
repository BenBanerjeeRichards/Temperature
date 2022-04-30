import json
from random import randint 
import datetime 
import boto3 

dynamo = boto3.client("dynamodb")
db_table = "temperature"

def lambda_handler(evt, context):
    event = json.loads(evt["body"])
    print("Body=", event, evt)
    if "nonce" not in event or "temperature" not in event or "timestamp" not in event or "sensor_id" not in event:
        print("Malformed request as not all required fields are provided", event)    

        return {
            "statusCode": 400,
            "message": "Malformed request - not all required fields provided"
        }
    nonce = str(event["nonce"])
    existing_item = dynamo.get_item(TableName=db_table, Key={"id": {"S": nonce}})
    if "Item" in existing_item:
        print(f"Nonce already seen {nonce}")
        return {
            "statusCode": 400,
            "message": f"Item with nonce {nonce} already seen"
        }
    timestamp = datetime.datetime.fromtimestamp(int(event["timestamp"])).isoformat()
    res = dynamo.put_item(TableName=db_table, Item={
        "id": {"S": str(nonce)},
        "datetime": {"S": timestamp},
        "temperature": {"N": str(event["temperature"])},
        "sensor_id": {"S": str(event["sensor_id"])}
    })
    print(res)
    return {"statusCode": 200}

    
