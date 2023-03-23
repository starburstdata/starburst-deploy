#!/bin/bash
export secrets_file=secrets.yaml

# Clear existing secrets file
echo "" > $secrets_file

# Set new Secrets file
echo "apiVersion: v1" >> $secrets_file
echo "kind: Secret" >> $secrets_file
echo "metadata:" >> $secrets_file
echo "  name: environment-vars" >> $secrets_file
echo "type: Opaque" >> $secrets_file
echo "data:" >> $secrets_file

# Set Insights Databse values
echo "  # Insights Database" >> $secrets_file
for i in "database_username" "database_password" "database_connection_url"
do
    [[ ! -z $(eval echo -n "$"$(echo $i)) ]] && echo " " $i: $(eval echo -n "$"$(echo $i) | base64) >> $secrets_file
done

# Set Data Products
echo "  # Data Products" >> $secrets_file
for i in "data_products_enabled" "data_products_jdbc_url" "data_products_username" "data_products_password"
do
    [[ ! -z $(eval echo -n "$"$(echo $i)) ]] && echo " " $i: $(eval echo -n "$"$(echo $i) | base64) >> $secrets_file
done

# Starburst Access Control
echo "  # Starburst Access Control" >> $secrets_file
for i in "starburst_access_control_enabled" "starburst_access_control_authorized_users"
do
    [[ ! -z $(eval echo -n "$"$(echo $i)) ]] && echo " " $i: $(eval echo -n "$"$(echo $i) | base64) >> $secrets_file
done

# Registry User
echo "  # Registry User" >> $secrets_file
for i in "registry_usr" "registry_pwd"
do
    [[ ! -z $(eval echo -n "$"$(echo $i)) ]] && echo " " $i: $(eval echo -n "$"$(echo $i) | base64) >> $secrets_file
done

# Starburst Admin User
echo "  # Starburst Admin User" >> $secrets_file
for i in "admin_usr" "admin_pwd"
do
    [[ ! -z $(eval echo -n "$"$(echo $i)) ]] && echo " " $i: $(eval echo -n "$"$(echo $i) | base64) >> $secrets_file
done

echo
echo "--------------------"
echo "Secrets file created"
echo "--------------------"
cat $secrets_file
echo