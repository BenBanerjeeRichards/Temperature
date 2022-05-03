# Temperature sensor 

Code for ESP is inside `src/`

All AWS related things (including lambda code) is in `terraform/`

If you wish to to use this code, you will need to create two files

1. `src/secrets.h` - this should declare the following preprocessor constants: 
   - `SENSOR_ID` - a number of your choice to identify the sensor
   - `WIFI_SSID` - name of the WiFi network
   - `WIFI_PASSWORD` - WiFi password
2. `src/terraform.tfvars` - this should declare the following terraform variables
   -  `aws_access_key` and `aws_secret_key` - keys for an IAM user with sufficient permissions 
   -  account_id - your aws account id
