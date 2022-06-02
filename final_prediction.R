library(yaml)
library(argparser)
library(caret)
library(preprint)

config <- read_yaml('../workflow/config.yaml')

cell_line <- 'K562'

# Load the profiles
profiles_train <- readRDS(paste0(config$data_dir, '/', cell_line, '/data_R/profiles_train.rds'))
profiles_test <- readRDS(paste0(config$data_dir, '/', cell_line, '/data_R/profiles_test.rds'))

characteristic_profiles <- aggregate_profiles(profiles_train)
train_data <- pattern_likelihoods(profiles_train, characteristic_profiles, measure = 'Bayesian')
test_data <- pattern_likelihoods(profiles_test, characteristic_profiles, measure = 'Bayesian')

train_labels <- as.factor(ifelse(profile_type(train_data) == "enhancer", "enhancer", "not.enhancer"))
test_labels <- as.factor(ifelse(profile_type(test_data) == "enhancer", "enhancer", "not.enhancer"))

tuneGrid <- expand.grid(C = 2 ^ seq(-5, 8, length = 20), sigma = 1 / 45, Weight = 0.25)
fitControl <- trainControl(method = "cv", number = 5, classProbs = TRUE, verboseIter = TRUE)
model <- train(train_data, train_labels, method = 'svmRadialWeights',
                   trControl = fitControl, tuneGrid = tuneGrid)
pred <- predict(model, test_data)
print(model)
cat(paste0('Accuracy: ', sum(pred == test_labels) / length(test_labels), '\n'))

predictions <- pred
reference <- test_labels


print(confusionMatrix(data = unlist(predictions), reference = unlist(reference)))

fname <- paste0(config$data_dir, '/', cell_line, '/data_R/predictions.RData')
dir.create(dirname(fname), recursive = TRUE, showWarnings = FALSE)
save(predictions, reference, file = fname)
cat(paste0('Saved predictions to ', fname, '\n'))
