#!/bin/bash -e

# For details, see this page => https://docs.microsoft.com/en-us/azure/virtual-machines/linux/image-builder

## Setup
##################

tmpDir=tmp
imageName=linux-jdk11
imageVersion=1
imageFullName=${imageName}-${imageVersion}
srcRepoUrl=https://raw.githubusercontent.com/adybfadel/azure-image-builder/master/

# resource group name
sigResourceGroup=image-gallery-rg
# datacenter location
location=westus2
# name of the shared image gallery
sigName=image-gallery
# name of the image definition to be created
imageDefName=linux-vm-image
# additional region to replicate the image to
#additionalRegion=eastus
# image distribution metadata reference name
#runOutputName=linux-vm-image

mkdir -p $tmpDir

subscriptionID=$(az account show --query id --output tsv)
echo ""
echo "Subscription ID: "$subscriptionID
echo ""

echo "create the resource group"
az group create -n $sigResourceGroup -l $location


## Create a user-assigned identity and set permissions on the resource group
############################################################################

echo "create user assigned identity for image builder to access the storage account where the script is located"
identityName=image-builder-user-$(date +'%s')
az identity create -g $sigResourceGroup -n $identityName

echo "get identity id"
imgBuilderCliId=$(az identity show -g $sigResourceGroup -n $identityName --query clientId -o tsv)

echo "get the user identity URI, needed for the template"
imgBuilderId=/subscriptions/$subscriptionID/resourcegroups/$sigResourceGroup/providers/Microsoft.ManagedIdentity/userAssignedIdentities/$identityName

echo "download an Azure role definition template"
curl $srcRepoUrl/scripts/image-builder-roles.json -o $tmpDir/image-builder-roles.json
#cp json/image-builder-roles.json $tmpDir/image-builder-roles.json

imageRoleDefName="Image Builder Image Def"$(date +'%s')

echo "update the definition"
sed -i -e "s/<subscriptionID>/$subscriptionID/g" $tmpDir/image-builder-roles.json
sed -i -e "s/<rgName>/$sigResourceGroup/g" $tmpDir/image-builder-roles.json
sed -i -e "s/Azure Image Builder Service Image Creation Role/$imageRoleDefName/g" $tmpDir/image-builder-roles.json

echo "create role definitions"
az role definition create --role-definition ./$tmpDir/image-builder-roles.json

echo "grant role definition to the user assigned identity"
az role assignment create \
    --assignee $imgBuilderCliId \
    --role "$imageRoleDefName" \
    --scope /subscriptions/$subscriptionID/resourceGroups/$sigResourceGroup


## Create an image definition and gallery"
########################################

echo "create image gallery"
az sig create -g $sigResourceGroup --gallery-name $sigName

echo "create an image definition"
az sig image-definition create \
   -g $sigResourceGroup \
   --gallery-name $sigName \
   --gallery-image-definition $imageDefName \
   --publisher myIbPublisher \
   --offer myOffer \
   --sku 18.04-LTS \
   --os-type Linux

echo "download image template"
curl $srcRepoUrl/json/ubuntu1804-image-template.json -o $tmpDir/image-template.json
#cp json/ubuntu1804-image-template.json $tmpDir/image-template.json

sed -i -e "s/<subscriptionID>/$subscriptionID/g" $tmpDir/image-template.json
sed -i -e "s/<rgName>/$sigResourceGroup/g" $tmpDir/image-template.json
sed -i -e "s/<imageName>/$imageFullName/g" $tmpDir/image-template.json
sed -i -e "s/<sharedImageGalName>/$sigName/g" $tmpDir/image-template.json
sed -i -e "s/<region1>/$location/g" $tmpDir/image-template.json
sed -i -e "s/<region2>/$additionalregion/g" $tmpDir/image-template.json
sed -i -e "s/<runOutputName>/$runOutputName/g" $tmpDir/image-template.json
sed -i -e "s%<imgBuilderId>%$imgBuilderId%g" $tmpDir/image-template.json
sed -i -e "s/<srcRepoUrl>/$srcRepoUrl/g" $tmpDir/image-template.json

cat $tmpDir/image-template.json

## Create the image version
###########################

echo "submit the image configuration to the Azure Image Builder service"
az resource create \
    --resource-group $sigResourceGroup \
    --properties @image-template.json \
    --is-full-object \
    --resource-type Microsoft.VirtualMachineImages/imageTemplates \
    -n $imageFullName

echo "start the image build"
az resource invoke-action \
     --resource-group $sigResourceGroup \
     --resource-type  Microsoft.VirtualMachineImages/imageTemplates \
     -n $imageFullName \
     --action Run

echo "End."
#rm -rf $tmpDir