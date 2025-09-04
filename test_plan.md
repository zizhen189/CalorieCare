# 5.3 Test Plan & Test Cases

This section presents the test plan and detailed test cases developed to validate the functionalities of the CalorieCare system, covering all six modules, from the User Management Module to the Report Module. The test plan establishes a structured approach to testing, while the test cases define the steps, input data, and expected outcomes required to verify that each CalorieCare feature meets its specified requirements and operates correctly.

## 5.3.1 User Management Module

**Project Details**

| Student Name | Wang Zi Zhen | Programme: | RSD3S1 |
| :--- | :--- | :--- | :--- |
| **Project Title:** | CalorieCare: Diet and Nutrition Management System | **Test Case No:** | 1001 |
| **Module:** | User Management Module |
| **Actor(s):** | New User, Existing User |
| **Pre-requisites:** | - Internet connection available<br>- Firebase services are operational<br>- Application is installed and launched |
| **Dependencies:** | Firebase Authentication and Firestore services must be running |

**Test Case 1001:**

| No | Description | Test actions/ inputs | Expected | Actual Results | Pass(P)/ Fail(F) | Remarks |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| 1. | **Register User:** Verify new user registration with valid data for "Lose Weight" goal. | 1. Launch the app and navigate to the registration page.<br>2. Select goal: "Lose Weight".<br>3. Enter valid user details (gender, DOB, height: 175cm, weight: 80kg, target weight: 70kg, activity level: moderate).<br>4. Enter a unique email and a strong password.<br>5. Submit the registration form. | 1. User is successfully created in Firebase Authentication.<br>2. A new document is created in the 'User' collection with correct data.<br>3. A new document is created in the 'Target' collection with `TargetType: 'lose'`.<br>4. User is redirected to the home page. | | | |
| 2. | **Register User (Existing Email):** Verify registration with an existing email. | 1. Navigate to the registration page.<br>2. Enter an email that is already registered.<br>3. Fill in other fields with valid data.<br>4. Submit the form. | An error message "This email address is already registered" is displayed. Registration fails. | | | |
| 3. | **Register User (Goal Validation):** Verify goal validation for an overweight user selecting "Gain Weight". | 1. Start registration.<br>2. Enter height: 170cm and weight: 85kg (BMI > 25).<br>3. Select goal: "Gain Weight".<br>4. Proceed to the next step. | A warning dialog appears, recommending a "Weight Loss" goal. The user is prompted to accept the recommendation, which changes the goal to 'lose'. | | | |
| 4. | **Set Target:** Verify that the user's selected goal and target weight are stored correctly. | 1. During registration, select "Gain Weight" goal.<br>2. Enter current weight: 60kg and target weight: 65kg.<br>3. Complete registration. | The 'Target' document in Firestore for the user should have `TargetType: 'gain'` and `TargetWeight: 65`. | | | |
| 5. | **Calculate BMI:** Verify BMI calculation during registration. | 1. During registration, enter height: 175 cm and weight: 70 kg.<br>2. Proceed to the BMI calculation step. | The BMI is calculated correctly as 22.9 and displayed on the BMI screen. | | | |
| 6. | **Calculate Target Calorie:** Verify target calorie calculation during registration. | 1. Complete the registration process with specific data (e.g., Male, 25 years, 175cm, 70kg, moderate activity, maintain weight goal). | The daily calorie target is calculated based on the Mifflin-St Jeor equation (~2434 kcal) and displayed on the summary screen and homepage. | | | |
| 7. | **Edit Profile:** Verify that an existing user can update their profile information. | 1. Log in as an existing user.<br>2. Navigate to the profile page and tap "Edit Profile".<br>3. Change height to 180cm and activity level to 'light'.<br>4. Save the changes. | 1. The 'User' document in Firestore is updated with the new height and activity level.<br>2. The TDEE and Target Calories are recalculated and updated in the 'User' and 'Target' collections.<br>3. The user session is updated with the new information. | | | |
| 8. | **Edit Profile (Goal Change):** Verify that changing the goal recalculates target calories. | 1. Log in and navigate to "Edit Profile".<br>2. Change the goal from "Maintain Weight" to "Weight Loss".<br>3. Set a new valid target weight.<br>4. Save the changes. | The `TargetType` in the 'Target' collection is updated to 'loss', and the `TargetCalories` are reduced (e.g., by ~500 kcal) to create a deficit. | | | |

## 5.3.2 Security Module

**Project Details**

| Student Name | Wang Zi Zhen | Programme: | RSD3S1 |
| :--- | :--- | :--- | :--- |
| **Project Title:** | CalorieCare: Diet and Nutrition Management System | **Test Case No:** | 1002 |
| **Module:** | Security Module |
| **Actor(s):** | New User, Existing User |
| **Pre-requisites:** | - User has an account.<br>- Internet connection is available. |
| **Dependencies:** | Firebase Authentication |

**Test Case 1002:**

| No | Description | Test actions/ inputs | Expected | Actual Results | Pass(P)/ Fail(F) | Remarks |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| 1. | **Authenticate User:** Verify successful login with valid credentials. | 1. Launch the app and navigate to the login page.<br>2. Enter a registered email and the correct password.<br>3. Tap the "LOGIN" button. | The user is successfully authenticated, user data is fetched from Firestore, the session is saved, and the user is redirected to the homepage. | | | |
| 2. | **Authenticate User (Incorrect Password):** Verify unsuccessful login with an incorrect password. | 1. Navigate to the login page.<br>2. Enter a registered email and an incorrect password.<br>3. Tap the "LOGIN" button. | An error message "Wrong password." or "Invalid email or password." is displayed. The user remains on the login page. | | | |
| 3. | **Authenticate User (Account Lockout):** Verify account lockout after multiple failed attempts. | 1. On the login page, enter a registered email and an incorrect password 5 times consecutively. | After the 5th failed attempt, an error message "Account locked for 5 seconds..." is displayed. The "LOGIN" button becomes disabled or unresponsive for 5 seconds. | | | |
| 4. | **Authorize User:** Verify that a logged-in user can access protected pages. | 1. Log in successfully.<br>2. Attempt to navigate to the Profile Page or Progress Page. | The user can access these pages without being prompted to log in again. | | | |
| 5. | **Authorize User (Logged Out):** Verify that a logged-out user cannot access protected pages. | 1. Ensure the user is logged out.<br>2. Attempt to directly access the Profile Page URL/route. | The user is redirected to the login page. | | | |
| 6. | **Recover Password:** Verify the password recovery flow. | 1. On the login page, tap "Forgot Password?".<br>2. Enter a registered email address and submit.<br>3. Open the email and get the verification code/link.<br>4. Enter the code on the verification page.<br>5. Enter and confirm a new password on the reset page. | 1. A password reset email is sent successfully.<br>2. The verification code is accepted.<br>3. The password is changed in Firebase Authentication.<br>4. The user can log in with the new password. | | | |
| 7. | **Recover Password (Invalid Code):** Verify entering an invalid reset code. | 1. Initiate the password reset process and receive a code.<br>2. On the verification page, enter an incorrect or expired code. | An error message "Invalid verification code or link" is displayed. The user cannot proceed to the password reset page. | | | |

## 5.3.3 Smart Food Tracking Module

**Project Details**

| Student Name | Wang Zi Zhen | Programme: | RSD3S1 |
| :--- | :--- | :--- | :--- |
| **Project Title:** | CalorieCare: Diet and Nutrition Management System | **Test Case No:** | 1003 |
| **Module:** | Smart Food Tracking Module |
| **Actor(s):** | Existing User |
| **Pre-requisites:** | - User is logged in.<br>- Internet connection is available. |
| **Dependencies:** | - Firebase Firestore<br>- Gemini API for food recognition |

**Test Case 1003:**

| No | Description | Test actions/ inputs | Expected | Actual Results | Pass(P)/ Fail(F) | Remarks |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| 1. | **Log Food:** Verify that a user can search for and log a food item manually. | 1. On the homepage, select a meal type (e.g., "Breakfast").<br>2. On the Log Food page, search for "Apple".<br>3. Select "Apple" from the results.<br>4. In the modal, enter a quantity of 150g.<br>5. Tap "Add to Meal". | 1. The food item is added to the 'LogMealList' collection.<br>2. The 'LogMeal' document for today's breakfast is created or updated with the correct total calories.<br>3. The user is navigated back, and the homepage UI reflects the updated calorie intake. | | | |
| 2. | **Recognize Food:** Verify food recognition using a clear image from the camera. | 1. From the Log Food page, tap the camera icon.<br>2. Take a clear picture of a banana.<br>3. The app analyzes the image. | 1. The system correctly identifies the food as "Banana".<br>2. It matches it with an entry from the 'Food' database.<br>3. The nutritional information for the estimated portion size is displayed. | | | |
| 3. | **Recognize Food (Multiple Items):** Verify handling of an image with multiple food items. | 1. Take a picture containing an apple, a banana, and an orange.<br>2. The app analyzes the image. | The system identifies all three distinct food items and displays them in a list, each with its estimated nutritional information, allowing the user to select which ones to log. | | | |
| 4. | **Calculate Calorie:** Verify calorie calculation based on user-entered quantity. | 1. Search for a food with known nutrition (e.g., "Chicken Breast", 165 kcal per 100g).<br>2. In the modal, enter a quantity of 200g. | The modal correctly calculates and displays the calories for the entered quantity (e.g., 330 kcal). | | | |
| 5. | **AI Nutrition Fetching:** Verify AI is used when a food is not found in the database. | 1. On the Log Food page, search for a rare or unique food item not in the database (e.g., "Durian Crepe").<br>2. When no results are found, tap the "Get AI Nutrition" button. | 1. The Gemini API is called with the food name.<br>2. A confirmation dialog appears with the AI-generated nutritional info.<br>3. Upon confirmation, the new food is added to the 'Food' database and then logged. | | | |


## 5.3.4 Dynamic Target Adjustment Module

**Project Details**

| Student Name | Wang Zi Zhen | Programme: | RSD3S1 |
| :--- | :--- | :--- | :--- |
| **Project Title:** | CalorieCare: Diet and Nutrition Management System | **Test Case No:** | 1004 |
| **Module:** | Dynamic Target Adjustment Module |
| **Actor(s):** | Existing User |
| **Pre-requisites:** | - User is logged in.<br>- User has logged food intake for the day. |
| **Dependencies:** | Firebase Firestore |

**Test Case 1004:**

| No | Description | Test actions/ inputs | Expected | Actual Results | Pass(P)/ Fail(F) | Remarks |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| 1. | **Check Daily Intake:** Verify the system correctly sums daily calorie intake. | 1. Log multiple food items for a single day (e.g., Breakfast: 300 kcal, Lunch: 500 kcal, Dinner: 700 kcal). | The homepage UI correctly displays the total consumed calories for the day as 1500 kcal. | | | |
| 2. | **Compare Target Intake:** Verify the comparison between consumed and target calories. | 1. Assume the user's daily target is 2000 kcal.<br>2. The user has consumed 1500 kcal. | The homepage UI correctly shows that the user has 500 kcal remaining for the day. | | | |
| 3. | **Auto Adjust Target:** Verify target adjustment when intake is higher than a "Weight Loss" target. | 1. User's goal is "Weight Loss" with a base target of 1800 kcal.<br>2. User logs 2200 kcal for the previous day.<br>3. The app is launched the next day, triggering the auto-adjustment service. | 1. A new 'CalorieAdjustment' document is created for the current day.<br>2. The new `AdjustTargetCalories` is calculated to be lower than the base target (e.g., 1800 - (2200-1800) = 1400 kcal).<br>3. The homepage displays the newly adjusted target. | | | |
| 4. | **Auto Adjust Target (No Adjustment):** Verify no adjustment when intake is lower than a "Weight Loss" target. | 1. User's goal is "Weight Loss" with a base target of 1800 kcal.<br>2. User logs 1600 kcal for the previous day.<br>3. The app is launched the next day. | No adjustment is performed because the user's intake was below their target, which aligns with the weight loss goal. The target on the homepage remains at 1800 kcal. | | | |
| 5. | **Auto Adjust Target (Weight Gain):** Verify target adjustment when intake is lower than a "Weight Gain" target. | 1. User's goal is "Weight Gain" with a base target of 2500 kcal.<br>2. User logs 2100 kcal for the previous day.<br>3. The app is launched the next day. | 1. A new 'CalorieAdjustment' document is created.<br>2. The new `AdjustTargetCalories` is calculated to be higher (e.g., 2500 + (2500-2100) = 2900 kcal) to compensate.<br>3. The homepage displays the new target. | | | |
| 6. | **Auto Adjust Target (Safety Boundaries):** Verify safety boundaries prevent dangerously low targets. | 1. User's goal is "Weight Loss" with a base target of 1800 kcal.<br>2. User logs an extremely high intake of 4000 kcal.<br>3. The app is launched the next day. | The new target is clamped by the safety boundary (e.g., BMR or a minimum of 1200/1500 kcal) and does not drop to a dangerously low value (e.g., -400 kcal). | | | |
| 7. | **Missed Adjustment Check:** Verify that a missed adjustment is performed on startup. | 1. Do not open the app for a full day where an adjustment should have occurred.<br>2. Launch the app the following day. | The `_checkMissedAdjustmentOnStartup` function is triggered, and the missed daily adjustment is calculated and applied for the previous day. | | | |

## 5.3.5 Motivation Module

**Project Details**

| Student Name | Wang Zi Zhen | Programme: | RSD3S1 |
| :--- | :--- | :--- | :--- |
| **Project Title:** | CalorieCare: Diet and Nutrition Management System | **Test Case No:** | 1005 |
| **Module:** | Motivation Module |
| **Actor(s):** | Existing User |
| **Pre-requisites:** | - User is logged in. |
| **Dependencies:** | - Firebase Firestore<br>- Firebase Cloud Messaging (FCM) |

**Test Case 1005:**

| No | Description | Test actions/ inputs | Expected | Actual Results | Pass(P)/ Fail(F) | Remarks |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| 1. | **Track Streak:** Increment streak on first log of the day. | 1. Ensure the user has not logged any food today.<br>2. Log a food item via Log Food page (any meal). | 1. A 'StreakRecord' exists for the user and CurrentStreakDays increments by 1 (or set to 1 if first ever).<br>2. LastLoggedDate is set to today (YYYY-MM-DD).<br>3. App navigates to the Streak Page showing a celebration animation and the updated streak. | | | |
| 2. | **Track Streak (Consecutive Days):** Maintain streak on consecutive days. | 1. Day 1: Log any food item (streak becomes N).<br>2. Day 2: Log any food item again. | CurrentStreakDays becomes N+1. The streak calendar shows two consecutive colored days. | | | |
| 3. | **Track Streak (Reset):** Reset after missed day. | 1. Day 1: Log any food item (streak becomes N).<br>2. Day 2: Do not log any item.<br>3. Day 3: Log any food item. | CurrentStreakDays resets to 1 on Day 3. LastLoggedDate updates to Day 3. | | | |
| 4. | **Track Streak (Update):** Verify that the streak is updated on the first log of a new day. | 1. Ensure no food has been logged for the current day.<br>2. Log any food item successfully. | 1. The user's streak is incremented.<br>2. The user is navigated to the Streak Page, which shows a celebration animation and the updated streak count. | | | |
| 5. | **Track Streak (Maintenance):** Verify that the streak is not updated again on subsequent logs the same day. | 1. After the first log of the day, log a second food item.<br>2. Observe the navigation after logging. | The food is logged successfully, but the user is navigated back to the homepage directly, without showing the Streak Page again. | | | |
| 6. | **Invite Friend:** Send supervision invitation. | 1. Navigate to Invite Supervisor page.<br>2. Search by username or email of another registered user.<br>3. Tap "Invite". | 1. A 'Supervision' document with Status='pending' is created and a unique SupervisionID is assigned.<br>2. Two 'SupervisionList' records are created (for inviter and invitee).<br>3. An RTDB notification is sent to the invitee; the invitee sees an invitation in the app. | | | |
| 7. | **Invite Friend (Blacklist):** Respect blacklist and existing relationships. | 1. From search results, tap block on a user and confirm.<br>2. Try searching/inviting that blocked user again.<br>3. If a supervision already exists (accepted/pending), try to invite again. | 1. A 'Blacklist' record is created; blocked user is excluded from search results and cannot be invited.<br>2. If an accepted/pending supervision exists, inviting the same user is prevented with an appropriate message. | | | |
| 8. | **Alert Friend:** Supervisor views user's streak after acceptance. | 1. Accept the pending supervision invitation (Status changes to 'accepted').<br>2. As the supervisor, open the supervised streak page. | Supervisor can view the user's current streak count and streak calendar. | | | |
| 9. | **Supervisor Streak:** Update supervisor streak when both log today. | 1. With an 'accepted' supervision, both users log food on the same day.<br>2. Trigger streak update (log action). | 'Supervision' record CurrentStreakDays increments by 1 and LastLoggedDate is today. If only one logs, supervisor streak does not increment. | | | |

## 5.3.6 Report Module

**Project Details**

| Student Name | Wang Zi Zhen | Programme: | RSD3S1 |
| :--- | :--- | :--- | :--- |
| **Project Title:** | CalorieCare: Diet and Nutrition Management System | **Test Case No:** | 1006 |
| **Module:** | Report Module |
| **Actor(s):** | Existing User |
| **Pre-requisites:** | - User is logged in.<br>- User has logged calorie intake and weight data over several days. |
| **Dependencies:** | Firebase Firestore |

**Test Case 1006:**

| No | Description | Test actions/ inputs | Expected | Actual Results | Pass(P)/ Fail(F) | Remarks |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| 1. | **View Calorie Intake:** Display daily calorie intake chart. | 1. Ensure multiple days have logged meals (different totals).<br>2. Navigate to Progress/Report page and select Calorie Intake view. | A chart (e.g., bar chart) shows daily calorie intake for the selected period (e.g., past week). The values match sums in 'LogMeal' per day. | | | |
| 2. | **View Weight Report:** Display weight progress chart. | 1. Ensure the user has multiple weight entries (from registration and subsequent logs).<br>2. Navigate to the Weight Report view. | A line chart displays weight over time using saved weight entries; the trend matches stored data. | | | |
| 3. | **Log New Weight:** Add current weight and update chart. | 1. In the weight report page, tap to add a new weight entry.<br>2. Enter valid weight (e.g., 68.5 kg) and save. | 1. A new weight entry is saved with today's date.<br>2. The weight chart updates immediately to include the new data point. | | | |
