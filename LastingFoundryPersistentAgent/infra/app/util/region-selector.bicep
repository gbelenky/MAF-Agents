// Region mapping for AI Services and model availability
// This module provides functions to select appropriate regions based on service and model requirements

// Map of regions where AI Services with specific models are available
var aiServicesRegionMap = {
  supported: [
    'eastus'
    'eastus2'
    'westus2'
    'westus3'
    'swedencentral'
    'northcentralus'
    'southcentralus'
  ]
  overrides: {
    westus: 'westus2'
    centralus: 'eastus2'
  }
  default: 'eastus2'
}

@export()
@description('Gets a supported region for AI Services based on model availability')
func getAiServicesRegion(location string, modelName string) string => 
  contains(aiServicesRegionMap.supported, location) 
    ? location 
    : (contains(aiServicesRegionMap.overrides, location) 
        ? aiServicesRegionMap.?overrides[location] ?? aiServicesRegionMap.default
        : aiServicesRegionMap.default)
