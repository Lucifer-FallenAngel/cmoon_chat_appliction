const { sequelize } = require('../config/db');

const User = require('./User')(sequelize);
const Conversation = require('./Conversation')(sequelize);
const Message = require('./Message')(sequelize);
const BlockedUser = require('./BlockedUser')(sequelize);

const db = {};
db.sequelize = sequelize;

db.User = User;
db.Conversation = Conversation;
db.Message = Message;
db.BlockedUser = BlockedUser;

module.exports = db;
