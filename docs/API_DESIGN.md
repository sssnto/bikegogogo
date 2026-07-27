# BikeGoGo API 设计

## 鉴权

应用支持设备绑定的访客账户和 Sign in with Apple。服务端只保存 `deviceId` 的 SHA-256
摘要，不保存设备原始标识。访问令牌是随机生成的 256 位令牌，服务端只保存令牌摘要，
默认 30 天过期；iOS 将原始令牌保存在 Keychain。

```http
POST /v1/auth/guest
Content-Type: application/json
```

```json
{
  "deviceId": "设备内持久化的 UUID",
  "displayName": "骑友-A1B2"
}
```

Apple 登录或把当前访客账户升级为 Apple 账户：

```http
POST /v1/auth/apple
Content-Type: application/json
Authorization: Bearer <当前访客 accessToken，可选>
```

```json
{
  "identityToken": "Apple 返回的签名 JWT",
  "rawNonce": "客户端本次登录生成的随机 nonce",
  "deviceId": "设备 Keychain 中的 UUID",
  "displayName": "Apple 首次授权返回的姓名"
}
```

服务端通过 Apple JWKS 验证 JWT 签名、`iss`、Bundle ID 对应的 `aud`、有效期和 nonce。
绑定已有访客会保留原用户 ID、好友码和好友关系。Apple 账户不能被另一个 Apple ID
覆盖绑定。

响应：

```json
{
  "accessToken": "随机会话令牌",
  "user": {
    "id": "usr_...",
    "displayName": "骑友-A1B2",
    "friendCode": "K7M2P9QX"
  }
}
```

除访客登录和健康检查外，账户相关接口需要：

```http
Authorization: Bearer <accessToken>
```

退出当前会话：

```http
DELETE /v1/session
Authorization: Bearer <accessToken>
```

当前用户：

```http
GET /v1/me
PATCH /v1/me
```

修改昵称请求：

```json
{
  "displayName": "周末骑手"
}
```

## 好友

```http
POST /v1/friends/requests
GET /v1/friends/requests
POST /v1/friends/requests/{requestId}/accept
POST /v1/friends/requests/{requestId}/reject
GET /v1/friends
```

发起申请：

```json
{
  "friendCode": "K7M2P9QX"
}
```

好友关系只有在接收方调用 `accept` 后建立。双方同时向对方发起申请时，第二次申请会自动
完成双向同意。

## 小队

```http
POST /v1/groups
GET /v1/groups
POST /v1/groups/{groupId}/members
DELETE /v1/groups/{groupId}/members/{userId}
```

## 语音

客户端通过后端换取 LiveKit token：

```http
POST /v1/voice/rooms/{friendUserId}/token
Authorization: Bearer <accessToken>
```

当前版本是一对一好友语音：双方必须已经互相同意并成为好友。后端再次校验好友关系，
再为双方生成相同且不可直接推导的房间名。客户端只提交发布/订阅权限，后端强制使用
当前账户的用户 ID 和昵称签发 2 小时 LiveKit 令牌。无会话返回 `401`，非好友返回 `403`。

```json
{
  "canPublish": true,
  "canSubscribe": true
}
```

响应：

```json
{
  "url": "wss://your-livekit-host",
  "token": "livekit-jwt",
  "roomName": "group_123"
}
```

## 骑行记录

```http
POST /v1/rides
PATCH /v1/rides/{rideId}
POST /v1/rides/{rideId}/points:batch
GET /v1/rides
GET /v1/rides/{rideId}
```

批量上传轨迹点：

```json
{
  "points": [
    {
      "latitude": 31.2304,
      "longitude": 121.4737,
      "elevationMeters": 8.0,
      "speedMetersPerSecond": 6.8,
      "timestamp": "2026-07-24T01:00:00Z"
    }
  ]
}
```
