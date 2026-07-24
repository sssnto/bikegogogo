# BikeGoGo API 设计

## 鉴权

MVP 可先使用 Apple 登录，后端签发自己的 JWT。

```http
POST /v1/auth/apple
```

响应：

```json
{
  "accessToken": "jwt",
  "user": {
    "id": "user_123",
    "displayName": "Peng"
  }
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
POST /v1/voice/rooms/{groupId}/token
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

